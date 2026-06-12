---
name: template-activity-host
description: >-
  Capability: 模板活动的主业务技能（写完后替换为：你的活动能做什么的一句话）。
  Use when: 用户出现 X / Y / Z 意图时（写完后替换）。
  Do not use when: 通用 runtime 调试或非本活动卡片维护。
license: MIT
---

# 模板活动主技能

本技能是活动业务的轻量路由入口。通用 runtime 只负责运行和校验共享输出；本技能负责活动业务路由、判断、生成和私有状态更新。

This activity runs in **card-system mode** (the runtime's only mode) with **typed-KV business data** (`runtime.json.data_schema_enabled = true`). Express all turn output by CALLING TOOLS — cards via `card_emit_template`, artifacts via `artifact_emit`, durable notes via `memory_add` (plus retract variants), `mark_status` only when finalizing the turn. Business state lives in `/instance/data.json` and is mutated through this activity's @tools (`tools.py::make_tools`) or the generic `data_*` tools. When done, just stop — the runtime assembles cards / state / artifacts / memory from your tool calls.

## Always Apply（必读，每轮先过一遍）

- **工具调用纪律**：activity-builder 包的 `<package>/policies/llm-output-discipline.md` 列出常踩的坑（assignment_id / artifact_id / kind / 沙箱路径）—— 写完 SKILL 时强烈建议引用
- 卡片协议见 `/activity/skills/<activity_id>-cards/SKILL.md`
- 详细规则变长时，拆到 skill-local supporting files：
  - `workflows/<flow>.md`
  - `policies/<policy>.md`
  - `references/<topic>.md`
  - `scripts/verify_output.py`

## 目标

根据用户输入推进一次智能活动，并通过工具调用产出可见卡片、产物、业务数据变更和短记忆。

复制本模板后，请把本节改成你的活动目标。例如：

- 帮用户完成一个计划。
- 主持一个互动游戏。
- 生成一份长文产物。
- 协作完成一个多轮任务。

## Fast Paths（典型路由表）

复制本模板后，把 `<id>` 改成你的 `activity_id`，照表执行即可覆盖大部分输入。复杂分支请下沉到 `workflows/`。

**关键**：`phase` 由 runtime 从每张卡的 `meta.phase` 字段自动派生——你**不**手动写 phase，而是在 `card_templates/<id>.<name>.json` 里给每张卡硬编码 `meta.phase`（welcome 卡写 `"phase": "welcome"`，result 卡写 `"phase": "completed"`，依此类推）。emit 卡片 *是* phase 转换的动作。
> **typed-KV 命名空间注脚**：上面说的是 runtime 派生的 `instance.data.phase`。它和你在 `data.schema.json` 里**自己声明的业务 `phase`**（typed-KV，用活动 @tool 直写推进、配相位守卫）是互不干扰的两个命名空间——后者合法且是官方推荐模式。模板卡不带 `meta.phase` 也合法（裁决后形态）。详见 `policies/output-protocol.md`「两个 phase 命名空间」。

| 触发条件 | 工具调用序列 | 终态信号 |
|---|---|---|
| state 为空 / 首次进入 | `card_emit_template("<id>.welcome", {...}, "<id>-welcome")` → 停 | 默认 `running`（不调 mark_status）|
| phase=intake 且用户已填关键字段 | 调本活动 @tools 写业务字段（如 `set_brief(topic=..., constraints=...)`）<br>→ **同 turn 内继续执行业务流水线** | （见下行）|
| phase=working → 业务完成 | 调业务工具 / 调 `image_generate` / 写 `artifact_emit`<br>`card_emit_template("<id>.result", {...}, "<id>-result")` *(result 卡的 meta.phase="completed" 会自动派生 phase)*<br>→ `mark_status("completed")` → 停 | 终态 `completed`（显式 mark_status）|
| 用户说"再来 / 重做 / 换一个" | 调 reset @tool 清空业务字段 → `card_emit_template("<id>.welcome", {...}, "<id>-welcome")` *(welcome 卡 meta.phase="welcome" 自动重置 phase)* → 停 | 默认 `running` |
| 工具失败（content filter / source 404） | **不改业务数据**；`card_emit_template("<id>.error", {reason: "..."}, "<id>-error")` 或 ad-hoc `card_emit(...)` → 停（一般保持 running 让用户重试）；不可恢复时 `mark_status("failed")` | 默认 `running`；不可恢复时 `failed` |
| 用户输入和上述都不匹配（闲聊兜底） | 只 emit 一张文本卡解释当前可做什么 → 停 | 默认 `running` |

> **End-of-turn HARD**：调完工具就停。所有用户可见输出经由 emit 工具落盘，runtime 在 turn 末汇编；content 里的任何文字都会被丢弃，无需也不应返回最终 JSON。

> **Turn boundary HARD**：一个完整的业务流水线（intake → working → completed）**必须在同一 turn 内完成**。可以中途 emit 一张 `<id>.progress` 卡（如"正在生成…"），但 turn 结束前必须 emit 终态卡——不要"emit progress 卡就停"，那会让用户卡在中间态。

> **assignment_id 跨 turn 一致**：表里所有 `assignment_id`（如 `<id>-result`）都从 `card_templates/*.json` 的字面值复制；同一逻辑卡在多 turn 中复用同一 ID，前端据此识别"这是更新不是新增"。

## 私有状态

`current_instance_state` 来自两部分：

**A. Runtime 自动派生** —— 在 `current_instance_state.data` 顶层（**LLM 写了也会被覆盖**）：
- `phase` ← 每张卡片的 `meta.phase` 自动派生（在 `card_templates/*.json` 里硬编码 phase）
- `turn_count` / `card_count` / `artifact_count` ← runtime 计数器
- `last_card_id` / `last_artifact_id` / `last_artifact_url` ← runtime 追踪

**B. 活动业务字段** —— 在 typed-KV `/instance/data.json`，由 `data.schema.json` 声明：

像 `brief`、`working_notes`、`stories` 这类业务字段由 LLM 通过活动 @tools（首选）或通用 `data_*` 工具写。例：

```python
# 首选：通过活动 @tool（在 tools.py::make_tools 里定义）
set_brief(topic="用户目标", constraints="用户约束")
add_working_note("中间观察 A")

# 兜底：通用 data_* 工具
data_set("brief", {"topic": "...", "constraints": "..."})
data_append("working_notes", "中间观察 A")
```

`x-auto-inject: true` 的字段会被 runtime 自动注入到系统提示——不必显式 `data_get` 读取。`x-auto-inject: false` 的字段（隐藏字段，如谜底、评分细则）必须 `data_get(key)` 才能读。

## 业务数据规则（HARD）

- **写已有 @tool 覆盖的字段时走对应 @tool**：例如活动定义了 `set_brief`，就调 `set_brief(...)`——它走统一的 schema 校验路径，并触发活动可能附带的多 store 副作用。
- **`phase` / 计数器 / `last_*_id` 由 runtime 派生**：`phase` / `turn_count` / `card_count` / `artifact_count` / `last_card_id` / `last_artifact_id` / `last_artifact_url` 全由 runtime 在 turn 末从已 emit 的卡片 / artifact 派生，业务侧无需也无法写入；phase 通过 emit 卡片的 `meta.phase` 自动推进。
- **数组追加用 `data_append`**：直接 `data_append(key, value)` 一步到位；避免 `data_get` + 修改 + `data_set` 三步循环（容易撞 race 且浪费 token）。
- **schema 失败时按报错改参数 retry**：每次 `data_set` / `data_append` / 活动 @tool 内部都会 dry-validate；失败时按 ToolMessage 报错调整参数再调，相同参数不重复重试。

## 产物规则（HARD）

短产物 markdown artifact，通过工具调用：

```text
artifact_emit({
    "artifact_id": "<kind>-<short-uuid>",
    "kind": "markdown",
    "title": "模板活动产物",
    "content": "# 模板活动产物\n\n这里是正文。",
    "mime_type": "text/markdown",
})
```

⚠️ **铁律**：
1. `artifact_id` **必填非空 string**（下游按 ID 解引用）
2. 图片产物：把 `image_generate` / `image_edit` 返回的 `file_url` 填进卡片变量；artifact 由 runtime live-artifact pipeline 自动收集（无需 `artifact_emit`）。

## 其他硬约束（HARD）

- **撤销机制**：同 turn 内可调 `card_retract(card_id)` / `artifact_retract(id)` / `memory_retract(id)` / `status_retract(id)`；跨 turn 不可撤。仅在确实察觉刚发错时调用，不要无目的反复撤回。业务数据写错了：直接用对应 @tool 提供的"修改"路径（如 `update_brief` / `delete_note`）或 `data_set(key, value)` 覆盖；typed-KV 写入幂等。
- **沙箱路径**：容器内**扁平挂载**——SKILL 路径 `/activity/skills/<skill-name>/SKILL.md`（**不是** `/activity/activities/<activity_id>/skills/...`），card_templates `/activity/card_templates/<name>.json`，turn 历史 `/instance/turns/<turn_id>/...` (ro)，工作区 `/instance/workspace/...` (rw)，业务数据 `/instance/data.json`（runtime 管理，不直接 read_file）。
- **记忆**：`memory_add(text)` 每轮 0-3 条，写短自然语言（`"用户输入 X；关键输出 Y"`），不要写 JSON / schema / 完整产物。已在 data.json / artifact 里的信息跳过。
- **简单 turn 工具白名单**：使用 `card_emit_template` / `card_emit` / `card_retract` / `artifact_emit` / `memory_add` / `mark_status` / 活动 @tools / `data_*` 通用工具及其撤销变体即可；`write_todos` / `execute` / `task` 留给复杂多步流水线，简单 turn 不调。

所有 11 个 card-system 工具的完整签名 + 错误模式：参考 activity-builder 包的 `<package>/references/card-system-tools.md`。typed-KV 工具签名 + 数据隔离合约：`<package>/references/data-store-tools.md`。（`<package>` = 你本地的 freedeepagents-activity-builder 安装目录，整包分发、外部可解析。）

## 输出要求

LLM 不返回任何最终 JSON。所有用户可见输出走 `card_emit*` / `artifact_emit` / `memory_add` / `mark_status`；所有业务字段走活动 @tools 或 `data_*` 通用工具写 `/instance/data.json`。Runtime 把这些汇编成 `ActivityAgentOutput` 发给前端。

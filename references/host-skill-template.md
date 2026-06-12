# Host skill template

Each activity has at least one host skill at `activities/<id>/skills/<id>-host/`. SKILL.md ≤120 lines; deeper content in `workflows/`, `policies/`, `references/`.

Activities run in **card-system mode** with **typed-KV business data** (`runtime.json.data_schema_enabled: true`). The LLM emits all side effects via tool calls (`card_emit_template`, `artifact_emit`, `memory_add`, retract variants) and mutates business state through activity @tools (or the generic `data_*` tools); writes land atomically in `/instance/data.json` and are validated against `data.schema.json` on every call. Runtime-derived state (phase / counts / last_*_id) is computed at turn end from emitted cards and surfaces via `current_instance_state`. When done, just stop — the runtime assembles the final `ActivityAgentOutput`.

> Activity @tool parameter annotations in `tools.py` must satisfy DeepSeek strict-mode JSON Schema: no bare `list` / `dict`; parameterized containers (`list[str]` / `list[dict]`) are legal, JSON-encoded `str` is the most cross-model-compatible fallback for complex payloads. See [../policies/llm-output-discipline.md](../policies/llm-output-discipline.md) §8d for the rules and self-check script.

## Directory layout

```
activities/<id>/skills/<id>-host/
├── SKILL.md                # thin router (≤120 lines)
├── workflows/              # one file per phase
│   ├── welcome.md
│   ├── playing.md
│   └── done.md
├── policies/               # red lines, budgets
│   ├── data-and-output.md
│   └── tool-budget.md
└── references/             # lookup tables
    └── ...
```

## SKILL.md template (≤120 lines)

```markdown
---
name: <id>-host
description: >-
  Use as the host policy for the <ActivityName> activity. Defines phase
  state machine, intent routing, and tool/output budget per turn. Loaded
  via manifest.skill_sources.
license: MIT
---

# <ActivityName> Host Skill

This activity runs in **card-system mode**. When done, just stop; the runtime assembles the rest from your tool calls.

## 当前状态

- `current_instance_state.data.phase` — runtime-derived phase from this turn's emitted card meta (or last turn's if no card emitted phase yet).
- `current_instance_state.data` 还包含 turn / card / artifact 计数器与 `last_*_id` 指针（runtime 派生）。
- Business data 通过 `data.schema.json` 中标了 `x-auto-inject: true` 的字段自动注入到 system prompt 顶部，可以直接读。隐藏字段（`x-auto-inject: false`，如谜底 / 评分细则）需要显式 `data_get(key)`。

## Phase 路由

| phase | 这一轮做什么 | workflow |
|---|---|---|
| welcome | 欢迎 + 收集首轮信息 | [workflows/welcome.md](workflows/welcome.md) |
| playing | 主循环 | [workflows/playing.md](workflows/playing.md) |
| done | 总结收尾 | [workflows/done.md](workflows/done.md) |

## 工具预算

每轮**最多**：
- N 次 image_generate / image_edit (仅当 manifest 声明 capability)

card-system 工具（`card_emit*`, `artifact_emit`, `memory_add`, `mark_status`, 撤销变体）不限额。活动 @tools（`tools.py` 里 `make_tools(ctx)` 暴露的那些）与通用 `data_*` 工具也不限额——业务写入应该多调，每次都即时校验。

详见 [policies/tool-budget.md](policies/tool-budget.md)。

## 输出契约

每轮：
- emit 至少 1 张 user-visible 卡片（除非纯状态转换 / 真正零输出）
- 通过活动 @tools（如 `add_note(...)`、`save_story(...)`）或通用 `data_*` 工具写业务字段；runtime-derived 字段（phase / counters / last_*_id）自动派生，不要写
- 终态时调一次 `mark_status("completed" | "failed")`；正常进行中保持默认 `running`（无需调 mark_status）
- **不返回任何最终 JSON**——调完工具就停。content 里写的任何文字都被丢弃

详见 [policies/data-and-output.md](policies/data-and-output.md)。

## 撤销机制

同 turn 内可撤回任何已 emit 的 entry，跨 turn 一律拒收：

- `card_retract(card_id)` / `artifact_retract(id)` / `memory_retract(id)` / `status_retract(id)`

业务数据写错了：用 @tool 提供的对应"修改"路径（如 `update_preferences`、`delete_note(note_id)`）覆盖，或者直接 `data_set(key, value)`。typed-KV 写入幂等。

调用任何 emit 工具时，返回值包含可用于撤回的 id。

## 硬约束

- 工具调用报错后修正参数再调；同一调用最多重试一次。
- welcome / smalltalk fast-path 路径只 emit 卡片就结束，不调外部工具。
- Phase 推进经过每一个中间状态，不跨越。
- 所有可见输出经由 card-system 工具（`card_emit*` / `artifact_emit` / `memory_add` 等）产出；发射 / 撤回的纪律见 [card-system-tools.md](card-system-tools.md)。
```

## workflow file template (e.g. workflows/playing.md)

```markdown
# Phase: playing

## Trigger

`current_instance_state.data.phase == "playing"`. User just sent input X.

## Steps

1. 读 auto-inject 的业务字段或 `data_get("hidden_key")` 拉隐藏字段（如果需要）。
2. 调活动 @tool 把业务变化写下去：`update_score(score=current+1)` / `add_attempt({...})` / etc.
3. `card_emit_template("<id>.result_card", {score, attempts, ...}, "<id>-result")`.
4. （可选）`memory_add("用户在第 N 局得分 X")`.

## Allowed tools this phase

- card_emit_template, card_retract, mark_status (终态轮)
- 活动 @tools（`tools.py` 里定义的那些用户语义写入工具）
- 通用 `data_get` / `data_set` / `data_append` / `data_delete` / `data_list_keys`
- image_edit (0 or 1 call, only if capability declared)

## Allowed state changes

- `score`, `attempts`, 其他业务字段 — 通过活动 @tools 或 `data_set`
- runtime-derived phase（`instance.data.phase`）NOT manually written — emit a card with `meta.phase="done"` to advance。若活动在 `data.schema.json` 自管一个业务 `phase`（推荐用于工具相位守卫），那是另一命名空间、由 @tools 直写——见 [output-protocol.md「两个 phase 命名空间」](../policies/output-protocol.md)
- 给 @tool 写相位守卫时，拒绝错误的 `hint` 要输出代码侧真理（当前 phase / 允许 phase / 可推进工具），别只指向本文档——见 [tool-error-protocol.md](../policies/tool-error-protocol.md)

## Output

Always emit `<id>.result_card` with vars: { score, attempts, ... }. Then stop. If this turn ends the activity, also call `mark_status("completed")` before stopping; otherwise default `running` (do NOT call mark_status).
```

## When to split into a cards skill

Split when the host SKILL.md exceeds 120 lines because of card-related content (catalog of templates, vars schemas, common card recipes). Then create:

```
activities/<id>/skills/<id>-cards/
├── SKILL.md            # cards entry (also ≤120 lines)
└── references/
    ├── card-variables.md     # what each *.vars.json field means
    └── block-recipes.md      # common block compositions
```

And add `"skills/<id>-cards"` to `manifest.skill_sources`.

## 设计自由

本模板只固定**契约骨架**（card-system 输出、typed-KV 写入路径、End-of-turn 纪律、phase 派生机制）。相位划分、卡片编排、工具粒度、玩法叙事全部由你的活动自行设计——不存在"标准活动形态"，平台契约（卡片渲染得出来、工具调用得生效、Web 产物接得准）是唯一边界。

# Reference — Card-system 工具权威对照表

> **定位**：本文件是 LLM 在 card-system 模式下能调的所有工具的**随包分发权威**——外部开发者以本文件 + `schemas/*.json` 为准（schema 与运行时模型由 `check_schema_sync` 三方守卫保持一致）。终极源头是平台仓库的 `app/card_system/tools.py`（外部不可达，仅维护者可对照）；若发现本文件与真实运行时行为不一致，按 bug 反馈而不是自行猜测。

## Contents

- 心智模型（State 两部分 · 11 工具总表）
- 各工具签名逐条（card_emit_template / card_emit / card_list_templates / card_retract / artifact_emit / artifact_retract / memory_add / memory_retract / mark_status / await_user / status_retract）
- 关键模式（指针）· Turn boundary（指针）· 错误响应约定 · 与图片工具的关系

> **Business data 在 typed-KV `/instance/data.json`**。通过活动 @tools（`tools.py::make_tools` 暴露的那些）或 `data_*` 通用工具读写——不通过卡片系统工具。typed-KV 工具签名见 [data-store-tools.md](data-store-tools.md)；本文件覆盖 card / artifact / memory / mark_status。

## 心智模型

Card-system 模式是新活动的运行模式（`runtime.json` 的合法字段见 `<package>/schemas/runtime.schema.json`）。LLM 通过下列工具表达副作用，runtime 在 turn 结束时从工具调用历史汇编最终 `ActivityAgentOutput`（包括从 emit 的卡片 / artifact 派生出 phase / counts / last_*_id）。完成时直接停，不返回任何最终 JSON。

**工具列表（11 个）**：

`card_emit_template` / `card_emit` / `card_list_templates` / `card_retract` / `artifact_emit` / `artifact_retract` / `memory_add` / `memory_retract` / `mark_status` / `await_user` / `status_retract`

四类副作用，每类一个发射 + 一个撤回（同 turn），加 `card_list_templates` 一个查询；外加 `mark_status` 标记终态：

| 类别 | 发射 | 撤回（同 turn）| 查询 |
|---|---|---|---|
| 卡片 | `card_emit` / `card_emit_template` | `card_retract` | `card_list_templates` |
| 产物 | `artifact_emit` | `artifact_retract` | — |
| 记忆 | `memory_add` | `memory_retract` | — |
| 终态 | `mark_status("completed" / "failed")` | `status_retract` | — |

### 🔑 State 由两部分组成

1. **Runtime-derived 字段**（在 `current_instance_state.data` 顶层）：由 runtime 在 turn 末从已发出的卡片 / artifact 自动派生进 `instance.data`；业务侧通过 emit 卡片 / artifact 间接影响，没有也无需写入工具。

   | 字段 | 派生来源 |
   |---|---|
   | `phase` | 本轮最后一张 card 的 `meta.phase`（在卡模板里硬编码） |
   | `last_card_id` | 本轮最后 emit 的 card 的 id |
   | `last_artifact_id` | 本轮最后 emit 的 artifact 的 id |
   | `last_artifact_url` | 本轮最后 emit 的 artifact 的 url（image_generate / image_edit 自动落） |
   | `turn_count` / `card_count` / `artifact_count` | runtime 计数器 |

   实现在平台仓库 `app/card_system/state_derivation.py`（外部不可达，路径供维护者对照）。

2. **业务字段**：活动自己定义，住在 typed-KV `/instance/data.json`，通过活动 @tools（首选）或 `data_*` 通用工具维护。字段形状完全由你的 `data.schema.json` 决定（谜底、故事列表、参考图 URL、日程……什么都行）。详见 [data-store-tools.md](data-store-tools.md)。

   > **typed-KV 里声明自己的 `phase` 业务字段是合法且推荐的**（多阶段活动配工具相位守卫的官方模式）。它和上表的 runtime-derived `phase` 是**两个互不干扰的命名空间**——runtime 的派生覆写只发生在 `instance.data`，从不触碰 typed-KV。完整裁决见 [output-protocol.md「两个 phase 命名空间」](../policies/output-protocol.md)。

---

## 1. `card_emit_template(template_id, variables, assignment_id=None)`

**首选发卡方式。** 渲染活动 `card_templates/<template_id>.json` 模板。

- **参数**：
  - `template_id: str` — 模板名（`card_templates/` 下文件 stem，如 `"<id>.story"`）
  - `variables: str` — **JSON-encoded 字符串**（不是 dict！），满足 `card_templates/<template_id>.vars.json` schema。LLM 通过工具调用 JSON 序列化时会自然产生字符串；本地 Python 调用需 `json.dumps(...)` 包一下。例：`'{"title":"...","body_markdown":"..."}'`
  - `assignment_id: str | None` — 通常**不**传，由模板内置的字面 ID 决定
- **返回**：`{card_id, seq, template, assignment_id, summary}`（或 `{error, available_templates}`）
- **典型调用**：
  ```text
  card_emit_template(
      "riddle-host.story",
      {"title": "小狐狸的暖梦", "body_markdown": "...", "image_url": "https://...", ...},
      "riddle-host-story-of-the-night",
  )
  ```
- **常见错误**：
  - `variables` 缺字段 / 类型错 → 返 error，附 `available_templates` 列出所有模板及必需变量
  - `template_id` 不存在 → 同上
- **何时不用**：用户输入完全偏离活动业务（闲聊兜底），且活动没有专门的 "smalltalk" 模板——这时用 `card_emit` 发一张 ad-hoc 文本卡。

## 2. `card_emit(card, assignment_id=None)`

**Ad-hoc 发卡**（紧急错误、闲聊兜底、突发情况）。优先用 `card_emit_template`；本工具只在没有合适模板时使用。

- **参数**：
  - `card: str` — **JSON-encoded 字符串**（不是 dict！）完整 `OutputCard` 或裸 `MinimalAICard`（`{version, template, blocks, meta}`）的 JSON。例：`'{"version":"1.0","template":"message","blocks":[{"type":"markdown","content":"..."}],"meta":{}}'`
  - `assignment_id: str | None` — 可选 routing key
- **返回**：`{card_id, seq, template, assignment_id, summary}`
- **典型调用**：
  ```text
  card_emit(
      {"template": "runtime.text", "version": "1.0",
       "blocks": [{"type": "markdown", "content": "我现在只能帮你做……"}],
       "meta": {}},
      assignment_id="smalltalk-fallback",
  )
  ```
- **常见错误**：blocks 用了白名单（6 种 type）以外的 type → 返 error，hint 告诉你用 `card_emit_template`。

## 3. `card_list_templates()`

**查询本活动所有模板**。LLM 不确定某模板存在时调一次；不要每轮调（浪费 token）。

- **参数**：无
- **返回**：`{templates: [{template_id, required_variables}, ...]}`

## 4. `card_retract(card_id)`

**同 turn 内** 撤回错发的卡。跨 turn 不可用。

- **参数**：`card_id: str` — `card_emit*` 返回的 ID
- **返回**：`{status: "retracted", card_id}`
- **何时用**：tool 调用前你乐观发了一张 progress 卡，结果业务路径变了——撤回后再发正确的终态卡。

---

## 5. `artifact_emit(artifact)`

**发 markdown / file artifact**（如长正文、用户可下载文件）。

- **参数**：`artifact: str` —— JSON-encoded OutputArtifact（与 `card_emit` / `variables` 同一约定；传 dict 也兼容但 str 最稳）。
  - 必含：`title`，以及 `path` / `content` / `url` 三选一
  - `kind`：`"markdown"`（默认）或 `"file"`
  - 可选：`artifact_id`（**省略时 runtime 自动从 title 生成 slug、否则 `artifact-<uuid8>`**）、`mime_type`、`description`
- **返回**：`{artifact_id, seq, kind, title, summary}`
- **典型调用**：
  ```text
  artifact_emit('{"kind":"markdown","title":"小狐狸的暖梦","content":"# 小狐狸的暖梦\\n\\n从前有一只小狐狸……","mime_type":"text/markdown"}')
  ```
- 图片产物走 runtime 自动 surface：`image_generate` / `image_edit` 返回的图片由 runtime live-artifact pipeline 登记，把返回的 `file_url` 填进卡片变量即可，不用再调 `artifact_emit`。
- **注意**：`artifact_id` 在 emit 时**非必填**（缺了 runtime 自动生成）。但**卡模板 / 示例 JSON 文件里**的静态 artifact 仍必须写非空 `artifact_id`（verifier 硬检查 #16）——那是包验收检查，不是本工具的运行时行为。

## 6. `artifact_retract(artifact_id)`

**同 turn 内** 撤回。参数 `artifact_id: str`，返回 `{status: "retracted", artifact_id}`。

---

## 7. `memory_add(text)`

**追加短期持久记忆**（跨 turn 保留）。每轮 0-3 条。

- **参数**：`text: str` — 非空，≤800 字符。建议格式：`"用户输入: ...；关键输出: ..."`
- **返回**：`{memory_id, seq, summary}`
- **何时用**：信息值得跨 turn 召回（用户偏好、关键事实），且不在 typed-KV / artifact 中。
- **何时不用**：内容已经在 typed-KV `data.json` 或 artifact 里——别重复。

## 8. `memory_retract(memory_id)`

**同 turn 内** 撤回。参数 `memory_id: str`。

---

## 9. `mark_status(status, note=None)`

**标记 turn 终态**：`"completed"` 表示活动这一轮目标达成、`"failed"` 表示不可恢复错误。默认 `status="running"`——不调即可。

- **何时用**：活动有终态（如游戏揭晓答案、咨询给出最终结论）。普通"中途进展"轮不调。
- 调完后整轮立刻结束 —— 任何额外的非 `memory_add` / `status_retract` 工具调用会触发 runtime short-circuit，原因会注入下一 turn 的 system prompt。

## 9b. `await_user(reason=None)`

**软停**：用来表达"这一轮已经把可发的卡发完，现在等用户输入下一步"。不会把 instance 推向终态（status 仍为 `running`），只是 runtime 在 turn 末读到这条记录后，下一 turn 的 system prompt 会带上 reason 当作 hint，提示模型继续多阶段流程。

- **何时用**：多阶段活动里某一阶段自然停留（如 intake 完一组问题，等用户答复后再进入 working 阶段）；不要拿它代替 `mark_status("completed")` 当终态。
- 与 `mark_status` 同属"本轮结束"信号，正常每轮只发一个。两者并非严格互斥——runtime 终态后的 allowlist 含 `mark_status` / `await_user` / `status_retract` / `memory_add`，所以一个软停（`await_user`）可以在同轮内升级成终态（`mark_status`）。但别把这当常规流程：先决定本轮是"软停等输入"还是"终结"，发对应那一个。
- 详见 `app/card_system/status_ops.py:await_user`。

## 10. `status_retract(status_id)`

**同 turn 内** 撤回 mark_status 或 await_user 写入。参数 `status_id: str`。

---

## 关键模式与 Turn boundary（指针）

调用纪律与踩坑的**权威是 [policies/llm-output-discipline.md](../policies/llm-output-discipline.md)**（§1 assignment_id 字面 ID、§2-4 artifact 字段、§7 turn boundary、§9 撤回心智）。在工具对照语境下最高频的三条：

- `assignment_id` 用模板顶层 hard-coded 的字面 ID，调用侧不拼序号；
- 图片 artifact 由 runtime 自动 surface，LLM 只填 `file_url` 进卡变量，不调 `artifact_emit`；
- 业务流水线同 turn 完成（progress 卡 → 终态卡 → retract progress → `mark_status` → 停）；真要跨多轮 = 活动状态机有多个稳定 phase，每个 phase 都要有可见输出卡。

---

## 错误响应约定

所有工具失败时返回 `{"error": "<message>", "hint"?: "<actionable fix>"}`。LangChain 把该字典当作 `ToolMessage(error=...)` 注入下一步上下文，LLM 应**修单条调用 retry**，不要把错误吞掉继续。

---

## 与图片工具的关系

`image_generate` / `image_edit` 是 capability 驱动的外部工具（不在上述 11 个 card-system 工具内），但它们的产物**自动**被 runtime 当作 artifact emit。详见 [workflows/03-image-tooling.md](../workflows/03-image-tooling.md)。

---

## 相关文件

随包分发（外部可解析）：

- 数据模型 schema：[schemas/card-template.schema.json](../schemas/card-template.schema.json) / [schemas/output-artifact.schema.json](../schemas/output-artifact.schema.json)
- LLM 易踩坑：[policies/llm-output-discipline.md](../policies/llm-output-discipline.md)
- 块类型与卡结构：[references/card-block-types.md](card-block-types.md)

平台仓库源头（仅维护者可达，路径供对照）：`app/card_system/tools.py`（工具实现）、
`app/card_system/assemble.py`（汇编逻辑）、`app/card_system/state_derivation.py`（state 派生）、
`app/models.py`（`CardBlock` / `MinimalAICard` / `OutputCard` / `ActivityAgentOutput`）。

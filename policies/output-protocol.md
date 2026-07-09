# Policy — Output Protocol (Card-System Mode)

## 一句话

**所有活动都通过 card-system 工具产出副作用，runtime 把工具调用记录 + 派生出来的 runtime state（phase / counts / last_*_id）汇编成符合 `activity-output.schema.json` 的 transport 对象发给前端。LLM 端零 schema：调完 emit 工具就停，不返回任何最终 JSON。**

---

## LLM 每轮该做什么

**不返回任何 JSON**。LLM 用 emit 工具表达所有产出，通过活动 @tools 或 `data_*` 工具维护 `/instance/data.json` 里的业务数据，调完即停。Runtime 从工具调用记录里组装最终输出。

工具调完后写在 content 里的任何文字都会被丢弃——不会到达用户也不会进 trace 的 user-visible 字段。如果想传"运维可见的备注"，用 `mark_status(status, note)` 的 `note` 参数。

终态如何表达：
- 默认 `instance.status="running"`——大多数 turn 不需要做任何额外动作
- 当 turn 把活动推到完成态：调一次 `mark_status("completed")` 后停止
- 当 turn 撞上不可恢复错误：调一次 `mark_status("failed", note="<reason>")` 后停止

零 emit 兜底：如果 turn 结束时 turn_dir 里没有任何工具调用记录，runtime 会自动塞一条 system 消息（"你必须 emit 卡片"）让 agent 重试一次；仍然零 emit 则 surface 一张固定的 `runtime.zero_emit_fallback` 卡片告诉用户重试。

---

## 运行时汇编后的 transport 对象（前端看到的形状）

通用层把工具调用拼成 `ActivityAgentOutput`：

```jsonc
{
  "schema_version": "2.0",
  "status": "<from mark_status emits; default 'running'>",
  "cards": [<OutputCard>, ...],          // 来自 card_emit / card_emit_template 调用
  "artifacts": [<OutputArtifact>, ...],   // 来自 artifact_emit (+ image_generate live-artifact pipeline)
  "state": {<derived dict>} | null,       // runtime-derived snapshot: phase / counts / last_*_id, 派生自本轮 emit 的卡片/artifact
  "memory_updates": ["<short>", ...],     // 来自 memory_add 调用
  "metadata": {}                          // runtime extensions only; activities should not write
}
```

详细字段含义见 [references/card-block-types.md](../references/card-block-types.md)。

## SSE 通道

Chat SSE 上的 event 类型来自 `RuntimeEventType`（`app/models.py`）。活动需要知道的几个：`run_started` / `turn_started` / `agent_started` / `agent_progress` / `card_item` / `artifact_item` / `state_committed` / `turn_completed` / `done`。两条新加事件：

- `dsl_updated`：payload 只带 `{"revision": "<8-char hash>"}`，告诉 chat 端"活动 DSL 变了"。完整 DSL 由 Static Preview SPA 通过 `/preview/<activity_type_id>/<activity_id>/api/dsl/stream` 单独订阅。
- `tool_invoked` / `tool_completed` / `llm_invoked` / `llm_completed`：受 `runtime.json.sse_debug_view.enabled` gate。带 `x-auto-inject: false` 字段的活动必须显式声明这个 config（见 [references/data-store-tools.md](../references/data-store-tools.md) §x-auto-inject）。

---

## 输出协议契约（违规→后果对照）

| 形态 | runtime 行为 |
|---|---|
| `manifest.json` / `runtime.json` 字段都来自白名单 | verifier 通过，runtime 加载活动 |
| 字段超出白名单 | verifier ERROR，runtime 拒绝加载该活动 |
| 工具调用入参符合 schema | 工具执行，副作用落到 turn workspace |
| 入参 schema 校验失败 | `ToolMessage(error=...)` 立即返回，按报错改正参数 retry |
| `card_emit_template` 引用已存在的模板名 | 模板渲染并 emit |
| 模板名不存在 | `ToolMessage(error=...)` 附 `available_templates` 提示 |
| `data_set` 写 schema 声明过的 key | 整 store dry-validate 后落盘 |
| 写未声明的 key（`additionalProperties: false` 下） | `ToolMessage(error=...)`，写入回滚，按 key 或 schema 修正后 retry |
| 所有可见输出走 emit 工具 | runtime 在 turn 末汇编 cards / artifacts / memory / status |
| content 里夹杂 JSON / 总结 / 自述意图 | 被丢弃（runtime 只读工具调用记录） |
| 推进活动到终态时显式 `mark_status("completed" / "failed")` | instance.status 设为目标态 |
| 不调 `mark_status` | instance.status 保持 `running`（默认） |

---

## ✅ state 编辑规则

业务字段住在 typed-KV `/instance/data.json`，由 `data.schema.json` 声明。Runtime-derived 字段（`phase`, `turn_count`, `card_count`, `artifact_count`, `last_card_id`, `last_artifact_id`, `last_artifact_url`）由 runtime 在 turn 末从本轮 emit 的卡片 / artifact 派生进 `instance.data`——**LLM 不写它们**。

```python
# 首选：活动 @tool（在 tools.py::make_tools 里定义；参数已经领域化）
add_note(content="...", tags=[...])
save_story(title="...", body="...", ...)

# 兜底：通用 data_* 工具
data_set("brief", {"topic": "...", "constraints": "..."})
data_append("working_notes", "中间观察 A")
data_get("hidden_key")  # 读 x-auto-inject:false 字段
```

**关键约束**：

1. 每次写入立即按 `data.schema.json` dry-validate；失败该写入回滚 + 返 `ToolMessage(error=...)`
2. 不要绕过 @tools 直接调 `data_set` 写已有 @tool 覆盖的字段（多 store 副作用会丢失）
3. 不要试图写 **runtime-derived** 字段——它们住在 `instance.data`，由 runtime 派生，没有写入工具（见下节「两个 phase 命名空间」；typed-KV 里的同名业务字段是另一回事，合法）
4. 切**展示层** phase 的方式：emit 一张 `meta.phase = "<目标值>"` 的卡片

详见 [references/data-store-tools.md](../references/data-store-tools.md)。

---

## ✅ 两个 phase 命名空间（规范性裁决）

`phase` 在系统里存在于**两个互不干扰的存储**，名字相同、用途不同。混淆它们是历史上最大的歧义源，以下为权威裁决：

| | **runtime-derived phase** | **typed-KV 业务 phase** |
|---|---|---|
| 住在哪 | `instance.data`（state.json），与 `turn_count` / `card_count` / `artifact_count` / `last_card_id` / `last_artifact_id` / `last_artifact_url` 共 7 个 runtime 字段 | `/instance/data.json`，由活动自己在 `data.schema.json` 声明（如 `enum: ["intake","drafting","completed"]`） |
| 谁写 | **只有 runtime**：turn 末取本轮最后一张带 `meta.phase` 的 emit 卡覆写；**本轮没有任何卡声明 `meta.phase` 时，沿用上一轮的值**（不会被清空），见 `app/card_system/state_derivation.py` | **只有活动**：@tools / `data_set` 直写 |
| 谁读 | 前端 transport / SSE / preview 的状态展示 | 活动 @tools 的相位守卫、AGENTS.md 路由判断（`x-auto-inject` 后注入 system prompt） |
| 互相影响 | **无**。runtime 的派生覆写只发生在 `instance.data`，**从不触碰** typed-KV 里任何键——包括名为 `phase` 的业务键 | 同左 |

**裁决结论**：

- 在 `data.schema.json` 里声明自己的 `phase` 字段并用活动 @tools 直写推进，是**合法且官方推荐**的模式——多阶段活动需要工具侧相位守卫时（"当前 phase 不是 X 就拒绝调用"），这是唯一被验证过、能让 LLM 行为可控的做法。runtime 不会覆写它。是否分相、分几相，完全是活动自己的设计。
- 文档里"不要写 phase、没有写入工具"这条红线，指的**只是** `instance.data` 里那份 runtime-derived phase——它确实没有写入工具，emit 卡的 `meta.phase` 是影响它的唯一途径。
- 两份 phase 各管一摊：`meta.phase` 决定**前端看到的阶段**；typed-KV phase 决定**工具守卫与路由**。多数活动应当两个都用，且让它们语义一致（emit 卡时顺手把 `meta.phase` 设成与业务 phase 同值）。
- **derived phase 的初始值**：首轮、且从未有任何卡声明过 `meta.phase` 时，runtime 取活动首个声明的 phase 作初值（state schema 的首个枚举值，由 runtime 以 `default_phase` 传入 `state_derivation`）；活动完全没声明 phase 时它保持 `None`。此后每轮只在"本轮有卡带 `meta.phase`"时才覆写，否则沿用上一轮——它不会被自动清空。
- **两份 phase 分歧时信哪份**：当活动同时维护两份且出现分歧，**工具相位守卫 / 业务路由以 typed-KV 业务 phase 为准**（它是活动自管、能被 @tool 守卫直接读取的真理），runtime-derived phase 只反映前端展示阶段。在 host SKILL 把路由建立在 typed-KV 业务 phase 上是**正确**的；两者应保持同步，持续分歧应视为活动 bug。不维护业务 phase 的简单活动则直接读 runtime-derived `current_instance_state.data.phase`，此时只有一份、不存在分歧。
- 其余 6 个 runtime 字段名（`turn_count` 等）同理：在 typed-KV 里征用同名做业务字段**不会冲突**，但为可读性建议避开。

---

## ✅ cards 规则

emit 一张固定模板：

```text
card_emit_template(
    "<activity_type_id>.intake",
    {"title": "...", "prompt_text": "..."},
    "<literal-assignment-id>",
)
```

emit 一张自由卡（罕用，模板更可靠）：

```text
card_emit({
    "version": "1.0",
    "template": "message",
    "blocks": [{"type": "markdown", "content": "..."}],
    "meta": {},
}, assignment_id="message-<seq>")
```

assignment_id 必须用模板 hard-coded 的字面 ID；自创会让前端把"同一逻辑卡"误判为多张。详见 [policies/llm-output-discipline.md](llm-output-discipline.md) §1。

---

## ✅ artifacts 规则

非图片 artifact（如 markdown 报告）：

```text
artifact_emit({
    "kind": "markdown",
    "title": "<title>",
    "content": "<body>",
    "artifact_id": "<stable-id>",       # 必填非空 string
    "mime_type": "text/markdown",
})
```

图片 artifact（`image_generate` / `image_edit` 的产出）：直接把返回的 `file_url` 填进卡片图片变量；artifact 由 runtime live-artifact pipeline 自动 surface（无需 `artifact_emit`）。

| Card | Artifact |
|---|---|
| 即时可见的 UI 块 | 持久化的文件 |
| 不一定有持久身份 | 有 `artifact_id`，可跨轮引用 |
| 以 block 数组组成 | markdown / file |

---

## 自检清单

- [ ] `runtime.json` 字段都来自 `<package>/schemas/runtime.schema.json` 白名单，含 `"data_schema_enabled": true`
- [ ] `data.schema.json` 含顶层 `default` + `properties` 覆盖所有业务字段；每个 key 有 `x-auto-inject` 显式声明
- [ ] host SKILL.md 用 `card_emit_template` / 活动 @tool 调用 / `artifact_emit` / `memory_add` 工具语法描述每个 sub-route：每条业务路径都对应一组具体工具调用，**不**在 prose 里出现 JSON 数组形式的输出指令（任何 `metadata.card_requests=[...]` / `state=[{...}]` 写法都属于把"应当通过工具调用产生的副作用"塞回了 prose，会被 verifier 软警告）
- [ ] 每张固定卡都用模板（`card_emit_template`），assignment_id 是字面常量
- [ ] image_generate / image_edit 的产出由 runtime 自动 surface；LLM 不调 `artifact_emit`
- [ ] verifier `python <package>/tools/activity_verifier.py` 输出 0 ERROR

---
name: template-activity-cards
description: 模板活动的卡片策略技能。复制本模板后，请替换为真实活动的卡片模板和变量规则。
---

# 模板活动卡片技能

本技能负责固定卡片模板、变量约定和可见卡片策略。顶层 `SKILL.md` 应保持轻量；如果变量表变长，请放到 `references/card-variables.md`。

This activity runs in **card-system mode**. Emit fixed templates via the `card_emit_template(template_id, variables, assignment_id)` tool. 卡片调用的三条铁律见下方。

## 模板字典（template_id → assignment_id）

复制本模板后请按你的活动改造本表。`<id>.welcome.json` 是同步到服务器并由前端直接展示的静态欢迎卡，文件名固定，卡片内不得出现任何 `{{变量}}`，对应 vars 必须为空。其他新增模板仍在 `card_templates/` 下放一对 `<id>.<name>.json` + `<id>.<name>.vars.json`，然后在本表加一行。

| template_id | assignment_id（字面） | 何时调用 | 必需变量 |
|---|---|---|---|
| `template-activity.welcome` | `template-welcome` | 首次进入 / 问候 / 重置完成 | **无；只能传 `{}`** |
| `template-activity.intake` | `template-intake` | state 为空 / phase=intake / 用户输入信息不足 | `title`, `body`, `topic`, `constraints` |
| `template-activity.result`（**示例位**，模板尚未提供该文件，请按真实活动添加）| `template-result` | phase=working 业务完成 | （由你的活动决定）|
| `template-activity.error`（**示例位**，按需添加）| `template-error` | 工具失败 / 不可救场景兜底 | `reason`（用户可读的一句话）|

调用样式（与上表一一对应）：

```text
card_emit_template(
    "template-activity.welcome",
    {},
    "template-welcome",
)

card_emit_template(
    "template-activity.intake",
    {
        "title": "请补充活动信息",
        "body": "告诉我你的目标、偏好和限制。",
        "topic": "",
        "constraints": "",
    },
    "template-intake",
)
```

## 变量

`template-activity.welcome` **不支持任何变量**。服务器同步时会把该 JSON 原样存储为活动类型的欢迎卡，前端不会经过 runtime 模板渲染就直接展示；因此 JSON 的任何位置都不得出现 `{{...}}`，`template-activity.welcome.vars.json` 必须保持 `properties: {}` 且 `additionalProperties: false`。

`template-activity.intake` 支持：

- `title`：卡片标题。
- `body`：说明文字。
- `topic`：用户目标默认值。
- `constraints`：用户约束默认值。

变量必须通过 `template-activity.intake.vars.json` 校验；缺失变量或类型错误会被 runtime 拒绝（`card_emit_template` 工具调用会返 error，LLM 自行修正后重试）。

## 卡片调用三条铁律

1. **`assignment_id` 用模板字面 ID**：从上表"字面"列复制一行；同一逻辑卡跨轮**复用同一 ID**，前端据此识别为"更新"而非"新增"。详见 activity-builder 包的 `<package>/policies/llm-output-discipline.md` § assignment_id。
2. **所有卡片走 `card_emit_template(...)` 工具调用**：runtime 自动从工具调用记录汇编 `cards: [...]`；活动侧只调工具，不构造数组、不写最终 JSON。
3. **`variables` 传已渲染的实际值**：`{{var}}` 只出现在 `card_templates/<id>.json` 模板源里；`card_emit_template(...)` 的 `variables` 参数直接传字面值（例如 `{"title": "请补充活动信息"}`）。

## 可见性规则

- 需要用户补充信息时，emit intake 卡片。
- 有短结果、状态摘要或下一步动作时，优先 emit 卡片。
- 长正文、报告、汇编内容不要塞进卡片，应通过 `artifact_emit` 发射 markdown / file artifact。

## 闲聊兜底

通用层会注入 smalltalk fallback：用户输入与本活动任何业务路由都不匹配时（问候 / 客套 / 闲扯），用一次 `card_emit({type: "markdown", content: "<text>"})` 回复即可。本活动如果有某些"看似闲聊实为业务"的输入（情绪信号、暗示用户意图等），在 host SKILL.md 里显式声明并覆盖默认。

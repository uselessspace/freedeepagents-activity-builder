# Reference — 卡片 Block 类型 + Artifact

> 卡片模板的完整 schema 在 `schemas/card-template.schema.json`。本文件是 Coding Agent 快速对照表。

## Contents

- 约束执行层级图例（🔴 pydantic / 🟡 verifier / ⚪ 约定）
- 6 种 Card Block：markdown · info · form (+FormField) · action · image · audio
- OutputCard 顶层结构
- OutputArtifact（关键约束）
- 固定模板（指针）· 输出契约要点 · assignment_id 跨轮约定（权威）

> **约束执行层级**（本文出现「必填 / 必须 / 不要」时，按此判断有多硬）：
> - 🔴 **pydantic 强制**：违反 → runtime emit 时 `OutputCard` 校验失败，卡发不出。这是最硬的一档，`schemas/card-template.schema.json` 逐字段镜像它（`tools/check_schema_sync.py` 保证两者同步）。
> - 🟡 **verifier 强制**：违反 → `python tools/activity_verifier.py` 报 ERROR（exit 1），ship 前必修；运行时不一定立刻炸。
> - ⚪ **仅约定**：pydantic / verifier 都不拦，但违反会降低质量或踩可读性坑（如 `title` 填空串能过校验但卡片难看）。
> 没标注的约束默认 🔴。

## 6 种 Card Block 类型

每个 OutputCard 由若干 block 组成。block `type` 必须在以下白名单：

`markdown` / `info` / `form` / `action` / `image` / `audio`

### 1. MarkdownBlock — 长文本 / 富文本

```jsonc
{
  "type": "markdown",
  "content": "## 标题\n\n正文段落，支持 **粗体** / *斜体* / [链接](url) / 代码块"
}
```

最常用。前端做 markdown 渲染。

### 2. InfoBlock — Key-Value 信息行

```jsonc
{
  "type": "info",
  "items": [
    { "label": "目的地", "value": "京都" },
    { "label": "时长", "value": "5 天 4 晚" }
  ]
}
```

适合短摘要 / 关键参数列表。

### 3. FormBlock — 表单

```jsonc
{
  "type": "form",
  "form_id": "<unique_id_within_card>",
  "submit_label": "提交",
  "fields": [
    {
      "name": "destination",
      "label": "目的地",
      "input_type": "text",      // ⚠️ HARD enum, see below
      "required": true,
      "placeholder": "例如：京都",
      "default_value": "",
      "multiple": false,         // file 字段：是否支持多选
      "accept": null             // file 字段：MIME 限制
    }
  ]
}
```

提交时前端把表单内容序列化成"提交表单 <form_id>"+ JSON 文本作为下一轮用户输入。文件作为同一 turn 的 upload。

#### FormField 字段白名单（StrictModel）

`FormField` 用 pydantic `StrictModel` 定义（权威源：随包分发的 `schemas/card-template.schema.json:FormField`，镜像运行时模型），只接受下表里的字段；其它字段会让 turn `OutputValidationError`。

| 字段 | 类型 / 取值 | 备注 |
|---|---|---|
| `name` | string | 必填 |
| `label` | string | 必填 |
| `input_type` | `text` / `textarea` / `number` / `file` / `audio` / `hidden` 之一 | 仅这六种；`audio` 渲染浏览器内录音控件（getUserMedia + WAV 编码），录音作为同 turn upload 提交，与 `file` 走同一通道；`hidden` 不渲染输入控件，但提交时会把 `default_value` 一起序列化 |
| `required` | bool | default false |
| `placeholder` | string \| null | |
| `default_value` | string \| null | |
| `multiple` | bool | 仅 file 类型有用 |
| `accept` | string \| null | 仅 file 类型有用，MIME 表达式 |

枚举选择有两条正路（FormField 没有 `options` 字段）：

1. **text + placeholder 提示**（最简单）：`{"input_type":"text","label":"性别（男/女/留空）","placeholder":"M / F / UNKNOWN"}`，host workflow 把自由文本映射到枚举。
2. **ActionBlock 按钮组替代 form**：每个枚举值做成一个 `action_type=input_text` 的按钮，用户点按钮就等于"选了这个值"。

`hidden` 字段只用于提交时携带非敏感上下文 ID（如 `memory_id`、`record_id`、`assignment_id`），让下一轮能把用户输入归属到正确对象。它不是安全边界：字段值仍存在于卡片 JSON、前端状态与提交文本中，不能放密钥、权限 token、隐私原文等敏感数据。活动 handler / skill 仍必须在服务端按当前实例状态校验这些 ID 是否有效。

### 4. ActionBlock — 按钮组

```jsonc
{
  "type": "action",
  "actions": [
    {
      "id": "confirm",
      "label": "确认行程",
      "action_type": "input_text",     // 自由字符串（pydantic 不约束取值，无封闭枚举）；约定用 input_text
      "payload": {
        "input_text": "我确认这版行程"  // 点击后这段文本作为下一轮用户输入
      }
    }
  ]
}
```

> **`action_type` 取值说明**：pydantic 侧它是普通 string（无封闭枚举，⚪ 仅约定）。
> 自带 chat 前端当前对所有 action 一视同仁：点击即把 `payload.input_text`（缺省依次回退
> `payload.text`、`label`）作为下一轮用户输入发送——所以 `input_text` 是唯一有约定语义的
> 取值，写别的值不会报错但也不会有特殊行为。Static Preview SPA 可自定义解释自己的
> `action_type`。

### 5. ImageBlock — 图片

```jsonc
{
  "type": "image",
  "images": [
    {
      "read_url": "https://... 或 sandbox 路径转出的 URL",
      "title": "<图片标题>",
      "description": "<图片描述>"
    }
  ],
  "min_images": 1                  // 可选；少于该数量校验失败
}
```

**字段权威源**：`schemas/card-template.schema.json:ImageItem`（镜像 `app/models.py:ImageItem`）。每个 ImageItem 含 `read_url` / `title` / `description` 三个 string 字段，契约与 AudioItem 完全一致。**执行层级**：`read_url` 必须存在（🔴 pydantic 强制）；`title` / `description` 可选（默认空串，🔴 schema 允许缺省），填有意义的内容只是 ⚪ 约定、让卡片更可读。`read_url` 为空字符串的条目会被前端自动过滤隐藏（与 AudioItem 同语义，用于"出图失败/跳过"时优雅降级——传空串即可，无需条件分支，不会出破图）。

前端不允许 base64 内嵌（避免 SSE 体积爆炸）。图片必须先上传到 object storage（artifacts 流）拿到 URL 再用。

### 6. AudioBlock — 音频播放

```jsonc
{
  "type": "audio",
  "audios": [
    {
      "read_url": "https://... 或 /v1/.../artifacts/<id>/content",
      "title": "🔊 朗读",      // 可选
      "description": ""          // 可选
    }
  ]
}
```

**字段权威源**：`schemas/card-template.schema.json:AudioItem`。三字段契约、执行层级、空串自动隐藏的优雅降级语义**与 ImageBlock 完全一致**（见上节）。前端渲染 `<audio controls>`。

音频 URL 通常来自 `tts_generate` 运行时能力（克隆声音朗读，结果 wav 上传 object storage）——详见 [`capabilities.md`](../policies/capabilities.md) 与 [`tts-tools.md`](tts-tools.md)。同样不允许 base64 内嵌。

---

## OutputCard 顶层结构

```jsonc
{
  "assignment_id": "<逻辑唯一 ID>",     // live update 时复用同一个 ID 表示"更新而非新增"
  "card": {
    "version": "1.0",
    "template": "<template id>",
    "blocks": [<block1>, <block2>, ...],
    "meta": {}
  }
}
```

---

## OutputArtifact — 文件型产物

artifact 是持久化的"文件"（markdown 报告、PDF、生成的图片等），跟 card 的区别：

- card 是即时 UI 块，没持久 ID
- artifact 有 `artifact_id`，可跨轮引用 / 增量更新

### Markdown Artifact

```jsonc
{
  "artifact_id": "story-20260513-abc123",   // 必填非空 string
  "kind": "markdown",                        // Literal["markdown","file"]
  "title": "京都 5 天行程 v1",
  "content": "# 京都行程\n\n## Day 1\n...",
  "mime_type": "text/markdown",              // 可选
  "description": null                        // 可选
}
```

### File Artifact

```jsonc
{
  "artifact_id": "img-de4d5f6a7b",          // image_generate 返回值的 artifact_id 直接用
  "kind": "file",                            // 图片一律用 file
  "title": "<title>",
  "url": "/v1/activity-types/<activity_type_id>/activities/<activity_id>/artifacts/img-de4d5f6a7b/content",  // 直接用 image_generate 返回的 file_url（始终是 /v1 代理，oss 私有桶也能加载）；或用 path（sandbox）
  "path": null,                              // sandbox 路径 /instance/artifacts/live/<turn>/xxx.png
  "mime_type": "image/png"                   // 可选
}
```

**字段权威源**：`schemas/output-artifact.schema.json`（镜像 `app/models.py:OutputArtifact`）。

> **关键约束**：
> - `artifact_id` 是必填非空 `str`，pydantic 会拒 null / 缺失。建议格式 `<kind>-<turn_id 前 12>` 或 `<kind>-<short uuid>`。
> - 图片 artifact 用 `kind="file"` + `url=` 或 `path=`；`kind="markdown"` 留给文本类 artifact，前端阅读器只在 `kind="file"` 时把它识别为图片资源。
> - 字段名是 `url`（非 `file_url`），StrictModel 拒未知字段。
> - `path` / `content` / `url` 三选一非空（model_validator 强制），否则报错 `artifact must specify path / content / url`。

---

## 固定模板 — 用 `card_emit_template` 工具

有 `card_templates/` 的活动**优先用模板**而不是手拼 cards。runtime 加载模板、用 vars 替换 `{{var_name}}`、渲染后进本轮汇编。工具签名 + 典型调用 + 错误形态的权威：[card-system-tools.md](card-system-tools.md)。

### 欢迎卡是静态同步契约（HARD）

每个活动必须提供 `card_templates/<activity_type_id>.welcome.json`。dev sync 会读取并原样存储这张卡，前端可在 activity turn 尚未运行时直接展示，因此它不是普通的运行时模板：

- JSON 任意位置都不得出现 `{{...}}` 模板占位符，所有欢迎文案、按钮和图片地址都必须是固定值。
- 同名 `<activity_type_id>.welcome.vars.json` 仍须存在以满足模板文件配对契约，但必须声明 `properties: {}`、无 `required` 项，且 `additionalProperties: false`。
- 运行时需要再次发出欢迎卡时，调用 `card_emit_template("<id>.welcome", {}, "<id>-welcome")`，variables 只能传空对象。
- 用户相关、实例相关或实时生成的内容放进后续 intake / result 等普通模板，不要放进欢迎卡。

---

## 输出契约（要点回顾）

- 6 种 block type 是封闭白名单（`markdown` / `info` / `form` / `action` / `image` / `audio`）
- artifact 必须含非空 `artifact_id`
- `form_id` / `assignment_id` 在同一 turn 内唯一
- `metadata` 字段保留给 runtime 扩展；业务数据通过 typed-KV 和 block 内容下传
- 每个 block / 字段都是 pydantic StrictModel — 设计模板前先翻随包分发的 [schemas/card-template.schema.json](../schemas/card-template.schema.json) 对应 `$defs`（`MarkdownBlock` / `InfoBlock` / `FormBlock` / `FormField` / `ActionBlock` / `ActionItem` / `ImageBlock` / `AudioBlock`）确认字段表，只用白名单字段（schema 与运行时模型由 `check_schema_sync` 三方守卫保持一致）

## assignment_id 跨轮约定（HARD）

```jsonc
{ "assignment_id": "<逻辑唯一 ID>", ... }
```

`assignment_id` 是逻辑卡片身份：**同一类卡片在不同 turn 重复出现时必须用同一个字面 ID**（如 `"family-welcome"`、`"family-member-added"`），通用层据此判定"live update 同一张卡而不是新增"。

写法：在 `card_templates/<name>.json` 顶层 hard-code `assignment_id`（如 `{"assignment_id": "<id>-welcome", "card": {...}}`），并在 host SKILL.md 里写明"必须用该字面 ID"。绝不在 `card_emit_template(...)` 调用时拼接序号（`welcome_card_1` / `_2` 这类会被前端误判为多张卡）。

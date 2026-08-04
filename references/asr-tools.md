# Reference — `asr`（音频转文字）

> 通用运行时能力。活动在 `manifest.capabilities` 声明 `asr` 后，Agent turn 才会得到 `transcribe_audio` 工具。

## 声明

```json
{"capabilities":["asr"],"input_modes":["text","file"]}
```

`file` 输入已支持 WAV、WebM、MP4/M4A、MP3 和 Ogg。不要新增 Activity 专属的录音输入字段；录音 UI 若需要，应作为独立的通用前端能力建设。

## 工具

```text
transcribe_audio(source_file_id, context="")
```

- `source_file_id` 必须是**本轮**用户上传的文件 ID（如 `file_0`）；不支持 URL、上一轮文件或任意 sandbox 路径。
- `context` 是可选的领域术语/近期上下文，最多 400 字符。
- `transcribe_audio` 成功时读取 `text`，并按活动自己的业务流程处理转写结果。不要依赖传输层响应形状或额外字段。
- 普通格式、网关或上游失败返回 `{"error", "hint"}`；不要在同一 turn 重试相同音频。

## 使用边界

只传入本轮附件 ID；不要传 URL、sandbox 路径或上一轮文件。活动代码不需要、也不应配置任何 ASR provider 参数。

`context` 最多 400 字符；录音过大、格式不支持或工具暂不可用时，直接向用户说明并请其在下一轮上传一段受支持的短录音。

活动 Skill 应定义“得到文本后如何处理”的业务策略；generic runtime 不解释转写文本。

Static Preview 的两种录音接入方式见
[preview-agent-turns.md](preview-agent-turns.md#将已上传录音附带到-agent-turn)
（由 Agent 转写）和 [preview-asr.md](preview-asr.md)（SPA 立即转写）。

| 需要谁决定后续流程 | 使用方式 |
| --- | --- |
| Agent，需要读取音频、调用 tools 或按照活动 Skill 处理文本 | `api/upload` 后把 `resource_ref` 放进 Agent Turn 的 `attachment_refs`；Agent 调用 `transcribe_audio(file_0)` |
| SPA，只需立即取得可编辑文本，可在之后任选是否提交 Agent Turn | multipart `POST api/asr`，提交 `audio` 和 `Idempotency-Key` |

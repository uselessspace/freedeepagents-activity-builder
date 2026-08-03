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

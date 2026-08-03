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
- `transcribe_audio` 成功返回 `text`、`provider`、`model`、`audio_duration_ms`、`billable_seconds`、`request_id`。Gateway V1 的 wire 响应将后三项放在 `usage` 中；FDA 运行时负责归一化，活动 Agent 不应依赖 wire 形状。
- 普通格式、网关或上游失败返回 `{"error", "hint"}`；不要在同一 turn 重试相同音频。
- gateway 返回 `402 + X-Billing-Cutoff: 1` 时，运行时会终止整个 turn；活动不得吞掉或伪装为普通转写失败。

## 安全和计费边界

FDA 只将已验证的本轮私有音频字节 Base64 转给 Go gateway `/v1/asr`。活动代码、sandbox 和 FDA 配置均不得持有百炼 Key、费率或余额逻辑。Go 使用固定 `fun-asr-flash-2026-06-15`，按实际音频时长向上取整秒数计费。

运行时默认限制：`ASR_MAX_SOURCE_BYTES=7MiB`、`ASR_MAX_PER_TURN=3`、`ASR_TIMEOUT=120` 秒、`ASR_MAX_CONTEXT_CHARS=400`。gateway 仍是权威校验方。

活动 Skill 应定义“得到文本后如何处理”的业务策略；generic runtime 不解释转写文本。

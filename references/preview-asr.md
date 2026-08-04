# Reference — Static Preview 直接 ASR

适用于 Static Preview SPA 在用户停止录音后，立即取得文字、展示并允许
编辑，再决定是否发起 Agent Turn 的场景。它不创建 Agent Turn，不依赖
`file_0`，也不调用浏览器 Web Speech。

活动必须同时声明 `dsl_builder_module` 和 `"capabilities": ["asr"]`。
未声明 `asr` 的活动调用此接口会得到 `404 asr_not_enabled`。

## 请求

```text
POST <preview-root>/api/asr
Content-Type: multipart/form-data
Idempotency-Key: <stable key for this recording>
```

FormData 字段：

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `audio` | 是 | 一段录音 Blob/File |
| `context` | 否 | 领域词或上下文，最多 400 字符 |

```ts
const form = new FormData()
form.append('audio', blob, 'recording.webm')
form.append('context', '可选的产品术语')

const response = await fetch(apiUrl('/asr'), {
  method: 'POST',
  headers: {'Idempotency-Key': crypto.randomUUID()},
  body: form,
})
```

不要手写 `Content-Type`；浏览器会写入 multipart boundary。可用 MIME：WAV、
WebM、MP4/M4A、MP3、Ogg（`audio/webm;codecs=opus` 也可）。单段原始音频
受部署端 ASR 源文件上限控制，默认 7 MiB；没有平台承诺的固定录音时长上限。

## 成功响应

```json
{
  "text": "转写后的文字",
  "provider": "dashscope",
  "model": "fun-asr-flash-2026-06-15",
  "audio_duration_ms": 1250,
  "billable_seconds": 2,
  "request_id": "asr_..."
}
```

## 身份与计费

浏览器始终通过 Go preview proxy 调用该路径。Go 清除浏览器携带的身份头，
注入可信身份并替换为短期 `fda-runtime` Bearer；FDA 用该 Bearer 调现有
ASR 网关。因此用户、活动和付款归属由 Go 决定，SPA **不得**提交 `user_id`
或任何 provider 凭证。

常见错误：`400 asr_audio_required` / `asr_audio_empty`、`415
unsupported_asr_audio`、`413 asr_audio_too_large`、`422
asr_context_too_long`、`402 billing_cutoff`、`502 asr_failed`、`503
asr_unavailable`。对于网络失败，使用相同 `Idempotency-Key` 重试同一段音频。

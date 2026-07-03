# Reference — `tts_generate`（文本转语音）

> 运行时能力。活动在 `manifest.capabilities` 里声明 `tts_generate` 即注入此工具。
> 权威实现：`app/tools/tts_gen.py` + 可插拔 provider `app/providers/tts/*`，注册见 `app/runner/__init__.py`。

## 一句话

把一段文本合成语音，结果上传 object storage（或 sandbox），返回可播放 URL。配 `audio` 卡片块直接播放。后端是**可插拔 provider**，由 `TTS_PROVIDER` 选择。

## Provider（`TTS_PROVIDER`）

| provider | 说明 | 需要 |
|---|---|---|
| `qwen`（默认）| DashScope **Qwen3-TTS 预置音色**（Serena/Cherry/Ethan/Chelsie…），快（~1-2s），云端 | `DASHSCOPE_API_KEY` |
| `cosyvoice` | 本地 CosyVoice 风格 `/api/tts_once`，**克隆**一段参考录音的音色，慢 | `TTS_ENDPOINT` + 一段参考 wav |

`qwen` 用**预置音色**（不克隆任意人声）；`cosyvoice` 用**录音克隆**。两者通过同一个工具调用，差别只在传 `voice` 还是 `reference_audio`+`prompt_text`。

## 声明

```jsonc
{ "activity_type_id": "my-activity", "capabilities": ["tts_generate"] }   // 可与 image_generate 并列
```

未声明 = 工具不存在。`TTS_ENABLED=false` 或 provider 未配置（如 qwen 缺 `DASHSCOPE_API_KEY`）时静默缺席（graceful degradation）。

## 工具签名

`tts_generate(text, voice="", reference_audio="", prompt_text="", store=None)`

| 参数 | 说明 |
|---|---|
| `text` | 要朗读的文本（纯文本最佳，去 markdown 符号）。上限 `TTS_MAX_TEXT_CHARS`。|
| `voice` | **预置音色名**（qwen 用，如 Serena）。留空用运行时默认音色。clone provider 忽略此参数。|
| `reference_audio` | **仅 clone provider**：实例里的参考录音（`/preview/.../uploads/<name>` URL）。可来自用户在预览页里自己录音上传——见 [user-upload.md](user-upload.md)。qwen 不用，留空。|
| `prompt_text` | **仅 clone provider**：参考录音的转写。qwen 不用，留空。|
| `store` | `auto`(默认) / `oss` / `sandbox`，语义权威见 [store-mode-table.md](store-mode-table.md)。|

**成功返回** `{"artifact": {artifact_id, store("oss" 或 "sandbox"), audio_url, storage_key(iff oss)|sandbox_path(iff sandbox), mime_type, byte_size, duration_ms}}`；`audio_url` 永远是 `/v1/.../content` 代理 URL（durable，见 store-mode-table.md），直接填进 `audio` 卡片块的 `read_url`。
**失败返回** `{"error": ..., "hint": ...}`——**不要重试同一文本**（provider 已决定，重试白费时间；失败会回滚配额，不占 per-turn 上限），照常出卡、`audio_url=""`（`audio` 块自动隐藏）。

## 配置（env vars）

| env | 默认 | 说明 |
|---|---|---|
| `TTS_ENABLED` | `true` | 全局开关 |
| `TTS_PROVIDER` | `qwen` | `qwen` / `cosyvoice` |
| `QWEN_TTS_MODEL` | `qwen3-tts-flash` | qwen 模型；`qwen3-tts-instruct-flash` 支持情绪/风格指令 |
| `QWEN_TTS_VOICE` | `Serena` | qwen 默认音色（`voice` 留空时用）|
| `TTS_ENDPOINT` | `http://192.168.1.225:50000/api/tts_once` | cosyvoice 克隆服务地址 |
| `TTS_TIMEOUT` | `300` | 单次合成超时（秒）；qwen 也用作下载音频的超时 |
| `TTS_MAX_PER_TURN` | `5` | 每轮合成次数上限 |
| `TTS_DEFAULT_STORE` | `auto` | 结果存储：auto/oss/sandbox |
| `TTS_MAX_TEXT_CHARS` | `6000` | 单次文本上限 |

`qwen` 复用 `DASHSCOPE_API_KEY`（与 image_generate 同一把 key）。

## 与 `audio` 卡片块配套

```jsonc
{ "type": "audio", "audios": [ { "read_url": "{{audio_url}}", "title": "🔊 朗读" } ] }
```

`audio_url` 为空字符串时该播放块自动隐藏——"配音失败"时把空串传进模板即可，无需在卡片里写条件分支。

## Static Preview / SPA 喇叭按钮

如果活动有 `site/`，不要让前端为了"点喇叭朗读"去发一轮特殊 turn（例如 `[TTS]` 标记）。在 Go 预览平面下，SPA 里的 origin-root `/v1/.../turns/stream` 路由可能不存在，容易表现为"调用 TTS 失败"。

推荐做法是 handler-first：

1. `manifest.json` 同时声明：

```jsonc
{
  "capabilities": ["tts_generate"],
  "handlers_module": "handlers"
}
```

2. `handlers.py` 通过 runtime 注入的 `ctx.tts_generate` 合成语音：

```python
def make_handlers(ctx):
    def tts(text: str = "") -> dict:
        body = (text or "").strip()
        if not body:
            return {"ok": False, "error": "text is required"}
        synth = getattr(ctx, "tts_generate", None)
        if synth is None:
            return {"ok": False, "error": "tts unavailable"}
        result = synth(text=body, store="auto")
        if not isinstance(result, dict) or result.get("error"):
            return {"ok": False, "error": (result or {}).get("error", "tts failed")}
        audio_url = (result.get("artifact") or {}).get("audio_url", "")
        return {"ok": bool(audio_url), "audio_url": audio_url, "error": "" if audio_url else "tts returned no audio"}

    return {"tts": tts}
```

3. 前端 POST 当前 preview 根路径下的 `api/tts`，例如用 `frontend-base/src/lib/api-base.ts` 的 `apiUrl('tts')`。不要硬编码 `/v1/...`，也不要用 `./api/tts` 依赖当前 SPA 子路由。

**直接使用返回的 `audio_url`**（`new Audio(url)` 或 `<audio src={url}>`）——不要硬编码 `/v1/...`、也不要自己拼 URL，平台会让它在当前预览环境下可访问。

## 新增 provider

仿 `app/providers/tts/qwen.py`：实现 `synthesize(*, text, voice, reference_path, prompt_text) -> TtsResult`，设 `requires_reference`，在 `app/providers/tts/__init__.py:create_tts_provider` 加分支。工具层无需改动。

## 计费 `tts_bill` SSE 字段

TTS **按字数(`char_count` = 合成文本长度)计费**,平行 `image_bill` / `llm_bill`。成功的 `tts_generate` 调用记录在 SSE done event payload 的 `tts_bill` 字段:

```jsonc
"tts_bill": {
  "calls": [
    { "seq": 1, "provider": "qwen", "model": "qwen3-tts-flash", "voice": "Serena",
      "char_count": 320, "byte_size": 51200, "duration_ms": 1800, "ts": "2026-06-..." }
  ],
  "totals": { "calls": 1, "chars": 320, "byte_size": 51200, "duration_ms": 1800 }
}
```

记账语义与 `image_bill` 完全平行（只记成功、失败走 `trace.jsonl` 的 `tts_gen_failed`、无调用不出现键、cost_ledger 持久化——结构详见 [image-tools.md](image-tools.md) §计费）；TTS 的差异：按字数计费，台账扁平列是 `tts_chars`。

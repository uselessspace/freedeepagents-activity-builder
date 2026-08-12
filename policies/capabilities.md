# Policy — Manifest `capabilities`（运行时通用能力 opt-in）

## 一句话

**`manifest.capabilities` 是活动声明"我要使用某个 runtime 通用工具"的白名单字段**。通用层（`app/tools/`、`app/providers/`）实现工具，活动通过列出 capability 名字 opt-in；verifier 拒绝白名单外的值。

---

## 当前可用的 capabilities

| capability | 注入的工具 | 触发的 runtime 模块 |
|---|---|---|
| `image_generate` | `image_generate` (langchain @tool) | `app/tools/image_gen.py` + `app/providers/image/*` |
| `image_edit` | `image_edit` (langchain @tool) | `app/tools/image_edit.py` + `app/providers/image/*` |
| `tts_generate` | `tts_generate` (langchain @tool) | `app/tools/tts_gen.py` + `app/providers/tts/*` |
| `read_document` | `read_document` (langchain @tool) | `app/tools/doc_ingest.py` + `app/providers/document/*` |
| `asr` | `transcribe_audio` (langchain @tool) | `app/tools/asr.py` + `app/providers/asr/*` |

`image_generate` / `image_edit` 共享 wanxiang provider 实例与同一 `IMAGE_GEN_MAX_PER_TURN` per-turn 计数器（详见 [`references/image-tools.md`](../references/image-tools.md)）。`tts_generate` 把文本合成语音、结果上传 object storage、返回播放 URL（配 `audio` 卡片块）；后端是可插拔 provider（`TTS_PROVIDER`：`qwen` 预置音色，默认 / `cosyvoice` 录音克隆），详见 [`references/tts-tools.md`](../references/tts-tools.md)。`read_document` 把上传的 PDF / Word / PowerPoint / Excel / HTML / CSV / JSON 转成 Markdown 供 agent 阅读（与图片源一致的 SSRF / 路径穿越 / 字节上限防护），详见 [`references/document-tools.md`](../references/document-tools.md)。

`asr` 把本轮私有音频附件转成文本；活动只需声明 capability 并调用 `transcribe_audio`。详见 [`references/asr-tools.md`](../references/asr-tools.md)。

Static Preview 另有 capability-gated 的直接入口：`POST api/asr` 接收录音
Blob 并立即返回文字，不创建 Agent Turn。若要让 Agent 决定如何处理录音，则先
`POST api/upload`，再通过 Preview Agent Turn `attachment_refs` 复制为本轮
`file_0`。两条路径分别见 [`preview-asr.md`](../references/preview-asr.md) 与
[`preview-agent-turns.md`](../references/preview-agent-turns.md)。`asr` 当前没有
`ctx.transcribe_audio` helper。

> **不是 capability 的能力**：活动代码在工具 / handler 内部做 side-channel LLM 调用（一次性文本生成、JSON 结构化、`vision` 看图）走 `ctx.llm`——它由 runtime 无条件注入、无需 manifest 声明，详见 [`references/ctx-llm.md`](../references/ctx-llm.md)。"看图分析"不要找 capability，也绝不要直连 provider（verifier 硬检查会拦）。

---

## 用法

manifest.json：

```jsonc
{
  "activity_type_id": "my-activity",
  ...,
  "capabilities": ["image_generate"]
}
```

声明后，运行时在创建 agent 时自动把 `image_generate` 工具注入 `tools` 列表。LLM 在 system prompt 里能看到工具描述（来自工具的 docstring），可以直接调用。

不声明 = 工具不存在。LLM 即使被告知"调 `image_generate`"也会得到"tool not found"错误。

> **同一 capability，入口并不完全对称**：`image_generate` / `image_edit` /
> `tts_generate` 同时提供 turn `@tool` 与 capability-gated ctx helper；
> `read_document` 只提供 turn `@tool`；`asr` 提供 turn 的
> `transcribe_audio` 和 Static Preview 的 `POST api/asr`，没有 ctx helper。
> 活动提示词只能承诺实际存在的那一面。
> `api/asr` 是平台预留入口；TTS 若由 SPA 直接触发，需要活动自己声明
> handler 并在其中调用 `ctx.tts_generate`，不存在通用的 direct-TTS endpoint。

---

## 优雅降级（声明 ≠ 一定可用）

声明 capability 是 opt-in；平台据此注入对应的 turn `@tool` 与 ctx helper。但若**平台没为该 capability 配好后端**（provider 未启用 / 凭证缺失），该工具与 helper 会**静默缺席**——声明不等于一定可用。活动代码必须能降级：

- **turn 内**：LLM 看不到该工具时，不要声称已经完成该操作；活动 Skill 应给出
  可见的 unavailable/改用上传或稍后重试路径。
- **handler / static-preview**：`getattr(ctx, "image_generate", None)` 为 `None` → 返回 `{"ok": False, "error": "...unavailable"}` 之类的优雅错误，别假设它一定存在。

哪些 env / 凭证决定可用性见各 capability 的 reference 文档；配没配好属运维侧，活动侧只管"拿不到就降级"。

---

## 硬约束

1. **Capability 事实源**：runtime 是 `app.models.ActivityManifest.capabilities`
   的 `Literal[...]`；Builder authoring gate 是
   `tools/activity_verifier.py:ALLOWED_CAPABILITIES` 与
   `schemas/manifest.schema.json`。`tools/check_schema_sync.py` 必须证明三者一致。
2. **Capability 名字保持通用运行时语义**：`image_generate`、`image_edit` 这种描述运行时机制的名字属于 capability；`generate_avatar_for_user_profile` 这种带活动业务语义的名字属于活动 @tool，在活动 `tools.py` 里以 @tool 暴露。
3. **每个 capability 对应一个具体的运行时工具**：capability = 一段可调用的能力（如 `image_generate` 工具），不是抽象意图（"提高 agent 智商"不是 capability）。

---

## 配套配置（per capability）

每个 capability 通常有一组 env vars 控制 provider 选择 / 限流 / 默认值。详见对应的 reference 文档：

| capability | 配置参考 |
|---|---|
| `image_generate` / `image_edit` | [`references/image-tools.md`](../references/image-tools.md) — `IMAGE_GEN_*` + `IMAGE_EDIT_*` env vars |
| `tts_generate` | [`references/tts-tools.md`](../references/tts-tools.md) — `TTS_PROVIDER` / `QWEN_TTS_MODEL` / `QWEN_TTS_VOICE` / `TTS_ENDPOINT` / `TTS_TIMEOUT` / `TTS_MAX_PER_TURN` / `TTS_DEFAULT_STORE` / `TTS_MAX_TEXT_CHARS` / `TTS_ENABLED` |
| `read_document` | [`references/document-tools.md`](../references/document-tools.md) — `DOC_INGEST_MAX_SOURCE_BYTES` / `DOC_INGEST_MAX_OUTPUT_CHARS` / `DOC_INGEST_MAX_PER_TURN` / `DOC_INGEST_URL_ALLOWLIST` env vars |
| `asr` | [`references/asr-tools.md`](../references/asr-tools.md) |

---

## verifier 检查

```bash
python3 <package>/tools/activity_verifier.py <project-root>
```

会针对每个活动 manifest：

- `capabilities` 必须是 list ✓
- 每个元素必须是 string ✓
- 每个元素必须在 `ALLOWED_CAPABILITIES` 集合内 ✓

任意一项失败 → error，活动不能完工。

---

## 新增 capability 的实施步骤（保持架构一致）

1. `app/tools/<capability_name>.py` 实现 `make_<capability>_tool()` 工厂
2. 如需 provider 适配，新建 `app/providers/<domain>/` 目录
3. `app/settings.py` 加该 capability 的 env vars
4. `app/runner/__init__.py` 在 capability 构建处加门控分支
5. `app/models.py:ActivityManifest.capabilities` 的 Literal 与 `tools/activity_verifier.py:ALLOWED_CAPABILITIES` 同步加新值
6. 写 `references/<capability>-tools.md` 给活动开发者看
7. 测试覆盖：单元 + factory 降级 + verifier 拒绝陌生值

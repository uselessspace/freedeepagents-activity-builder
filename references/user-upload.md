# Reference — 用户上传与持久化（`api/upload`）

> 平台级运行时能力，**不绑定任何活动**。任何声明了 `dsl_builder_module`（即有 Static Preview）的活动，SPA 都能直接用，无需各活动自己实现。
> 权威实现：`app/preview_dispatcher.py`（`POST api/upload` + `GET uploads/<name>`）。

## 一句话

让**使用预览页的终端用户**把图像、音频或文档作为当前实例的文件资源持久化。SPA `POST` 到当前预览根的 `api/upload`，拿到 opaque URL + `resource_ref`；平台负责持久化、回取与物理回收，"谁传的、放在哪、何时已无引用"由活动数据自己判断。完整资源契约见 [asset-lifecycle.md](asset-lifecycle.md)。

## 和其它"上传 / 产物"的区别

| 来源 | 谁产生 | 入口 | 用途 |
|---|---|---|---|
| **用户上传**（本文）| 预览页的终端用户 | SPA `POST api/upload` | 用户主动传的图 / 录音 |
| turn 文件 | 用户在对话里随消息带的文件 | `/v1/.../turns` 的 `files[]` | 当前 turn 的输入（见 image-tools 的 `source_file_id`）|
| 产物 artifact | agent / 工具（`image_generate`、`tts_generate`）| 运行时能力 | 模型生成的图 / 音 |

> handler 或系统产生的新字节可调用 `ctx.save_resource(content=..., content_type=...)`；用户确认后再落盘则走 `api/upload`。模型生成图、TTS 和文档转换本身已经是 artifact 资源，通常直接保存它们返回的 `resource_ref`，不必再次复制。统一读取/删除见 [asset-lifecycle.md](asset-lifecycle.md)。

## 请求

`POST <preview-root>/api/upload` —— 用 `frontend-base` 的 `apiUrl('upload')` 自动拼当前 `/preview` 或 `/dev/preview` 前缀。

- `multipart/form-data`，单个 `file` 字段。
- **直接用 `fetch` + `FormData`，不要走 `lib/http.ts` 的 `request()`**——后者强制 `Content-Type: application/json`，会破坏 multipart 边界。让浏览器自动带 boundary（别手动设 `Content-Type`）。

允许格式（精确匹配；`;codecs=…` 参数会被忽略后再校验）：

| 类 | MIME |
|---|---|
| 图像 | `image/png` `image/jpeg` `image/webp` `image/gif` |
| 音频 | `audio/wav` `audio/x-wav` `audio/wave` `audio/webm` `audio/mp4` `audio/mpeg` `audio/ogg` |
| 文档 | `application/pdf`、DOC/DOCX、XLS/XLSX、PPT/PPTX、`text/plain`、`text/markdown` |

- 浏览器 `MediaRecorder` 默认产 `audio/webm;codecs=opus`（Chrome/Firefox）或 `audio/mp4`（Safari），都被接受——**录音不用前端转码**。
- HTML / SVG / JS **一律拒**（415），避免同源 XSS；PDF 作为下载/文档资源允许。
- 超 `upload_max_bytes` → 413；空文件 → 400。成功上传本身就是正式 Preview
  交互：即使此前没有 turn，runtime 也会创建实例、记录可信操作者并更新
  `updated_at`。只打开页面或读取 DSL 不会创建空实例。

## 响应

```jsonc
{
  // opaque：默认可能 redirect 到对象存储（取决于部署的存储后端）。当不透明 URL 用，别解析、别假设同源。
  "url": "<preview-root>/uploads/<sha256>.<ext>",
  "asset_id": "<sha256>.<ext>",
  "upload_name": "<sha256>.<ext>",
  "resource_ref": { "kind": "upload", "activity_type_id": "…", "activity_id": "…", "upload_name": "<sha256>.<ext>" },
  "sha256": "…",
  "content_type": "audio/webm",
  "byte_size": 12345
}
```

- **内容寻址**：相同字节重复上传是幂等 no-op（同一个 `url`）。
- **资产标识**：`asset_id` 当前与 `upload_name` 相同；业务代码把它当 opaque ID，不要据此拼对象存储 key。
- **回取（URL 快速路）**：把 `url` 当 opaque 直接喂 `<img src>` / `<audio src>`（先过 `resolveAssetUrl()` 归一化前缀）。默认服务端可能 redirect 到存储后端；要同源拉字节加 `?proxy=true`。
- **持久化**：与产物同级耐久；实例硬删时随实例一起清除。
- **`resource_ref`**：跨平面 / 权限无关的引用。要支持同一实例跨 dev / 正式平面回放，优先把它和业务位置一起存进 `data.json`；`url` 可同时存作老客户端 / 本地调试兜底。
- **删除**：业务对象删除或替换文件后，先扫描完整实例确认资源已零引用，再调用 `ctx.delete_resource(resource_ref=resource_ref)`；失败会进入平台统一 GC。不要只删 URL 引用后留下孤儿，也不要在仍有其他引用时删物理文件。

## resource_ref 端到端

dsl_builder 不投影；也没有 `ctx.upload_url(resource_ref)` 这类 helper。投影发生在 Go 预览代理：FDA 返回 `api/dsl.json` / `api/<handler>` 的 JSON 后，Go 在鉴权通过的当前平面把对象里的 `resource_ref` 或 `resource_refs` 写回可访问 URL。

字段名不设媒体白名单。`resource_refs` 的 key 是**当前对象已有的直属字段名**（不是 JSONPath），因此 `src`、`image`、`photo`、`url`、`cover_url` 或活动自己的字段都能使用；`resource_ref` / `resource_refs` 两个协议字段本身不能成为投影目标。

FDA 在三个 Preview 出站面统一 enrichment：bootstrap `api/dsl.json`、DSL SSE full-mode、`api/<handler>` JSON。任意直属字符串字段只要**完整匹配** FDA canonical 资源 URL，就会自动得到 `resource_refs[field]`；外部 URL、夹在普通文本里的路径和不完整路径不会触发。已有卡片常用字段 `read_url / file_url / image_url / thumbnail_url / audio_url / trace_url` 仍保留对象级 `resource_ref` 兼容形状，但新活动的自定义 DSL 一律优先字段级映射。

最小配方：

1. SPA `POST api/upload` 后，把 `{resource_ref, url, page_index}` 发给业务 handler。
2. handler 把 `resource_ref` 存进 typed-KV；建议也存 `url` 作为调试兜底，但业务读取优先用 ref。
3. `dsl_builder` 原样带出一个媒体对象。若字段里仍有完整 canonical URL，FDA 会自动派生字段级 ref；若只保存了 ref，则显式输出 `resource_refs: {"<field>": ref}`，且 `<field>` 必须同时存在。
4. SPA 最终通常收到已投影后的 URL 字符串；仍统一过 `resolveAssetUrl()`，这样 direct FDA mount 和 Go developer proxy 都能显示。

```python
# handlers.py：保存上传归属
from app.card_system import data_store

def make_handlers(ctx):
    schema = data_store.load_data_schema(ctx.activity_dir)

    def save_page_recording(page_index: int, resource_ref: dict, url: str = "") -> dict:
        def mutate(data: dict) -> dict:
            recordings = data.setdefault("recordings", {})
            recordings[str(page_index)] = {
                "resource_ref": resource_ref,
                "url": url,  # fallback only; do not parse
                "author_user_id": ctx.user_id,
            }
            return data

        data_store.update_data(ctx.instance_dir, schema, mutate)
        ctx.notify_dsl_update()
        return {"ok": True}

    return {"save_page_recording": save_page_recording}
```

```python
# dsl_builder.py：新活动显式声明任意直属字段的投影目标
recording = data.get("recordings", {}).get(str(page_index), {})
audio = {
    "src": recording.get("url", ""),  # 字段必须存在；canonical URL 也便于本地调试
    "resource_refs": {"src": recording.get("resource_ref")},
}
```

如果同一个对象里有多个资源字段，分别写 `resource_refs.src`、`resource_refs.audio` 等映射；Go 逐字段投影，避免一个 ref 覆盖另一个字段。历史数据即使只有 `src: "/v1/..."` 而没有 ref，也会在出站时动态补出 `resource_refs.src`，无需迁移或复制文件。只有业务数据已经只剩 ref、没有 canonical URL 时，活动才必须手写字段映射。

## 归属：平台不管业务

平台负责**存字节 + 发 ref + 记录这次实例交互的可信操作者**，但 upload
资源记录本身没有活动业务的 `author_user_id`、页面位置或所有权字段。"谁上传、
属于绘本哪一页、谁能替换"仍由活动在 handler 中用 `ctx.user_id` 写进自己的
typed-KV。不要把实例交互审计误当成资源级业务归属或配额。

`ctx.user_name`（`str | None`）是调用者的**显示名**，来自 `X-FDA-User-Name` 头（percent-decoded）。仅用于界面展示 / 署名（如 "某某上传了…"）；身份校验、归属鉴权、配额管理仍须用 `ctx.user_id`。该字段 best-effort，头缺席时为 `None`——使用前必须判空。

典型流：

1. SPA `POST api/upload` → 拿 `resource_ref` / `url`；
2. SPA `POST api/<your_handler>`（带上 url + 业务位置，如 `page_index`）；
3. handler 校验 `ctx.user_id` 后把 `resource_ref`（和可选 `url` 兜底）落进 `data.json`；
4. `dsl_builder` 渲染时带出活动需要的直属字段（如 `src`）+ `resource_refs.src`，SPA 用 `resolveAssetUrl()` 显示。

## 上传录音后交给 Agent ASR

若录音要由 Agent 在**本轮**调用 `transcribe_audio`，上传完成后不要把
`url` 当作 `source_file_id`。将响应的 `resource_ref` 放在 Preview Agent
Turn 顶层的 `attachment_refs`；运行时会把同实例的 upload 复制成该 turn
的私有 `file_0`。完整请求例见 [preview-agent-turns.md](preview-agent-turns.md)。

若录完要立即显示可编辑文字、不启动 Agent，则直接调用平台的
[preview-asr.md](preview-asr.md) 接口。

## 录音 → 克隆朗读

用户录的音可直接喂 `tts_generate(reference_audio=<上传返回的 url>, prompt_text=…)`（clone provider），让 agent 用用户的声音朗读。见 [tts-tools.md](tts-tools.md)。

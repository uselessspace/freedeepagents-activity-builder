# Reference — 用户上传与持久化（`api/upload`）

> 平台级运行时能力，**不绑定任何活动**。任何声明了 `dsl_builder_module`（即有 Static Preview）的活动，SPA 都能直接用，无需各活动自己实现。
> 权威实现：`app/preview_dispatcher.py`（`POST api/upload` + `GET uploads/<name>`）。

## 一句话

让**使用预览页的终端用户**把自己产生的图像 / 录音上传并持久化（绘本工坊自己读绘本录的音、记忆档案馆传的照片）。SPA `POST` 到当前预览根的 `api/upload`，拿到一个 opaque URL + `resource_ref` + `asset_id`；平台负责持久化与回取，"谁传的、放在哪、何时已无引用"由你的活动数据自己判断。完整删除契约见 [asset-lifecycle.md](asset-lifecycle.md)。

## 和其它"上传 / 产物"的区别

| 来源 | 谁产生 | 入口 | 用途 |
|---|---|---|---|
| **用户上传**（本文）| 预览页的终端用户 | SPA `POST api/upload` | 用户主动传的图 / 录音 |
| turn 文件 | 用户在对话里随消息带的文件 | `/v1/.../turns` 的 `files[]` | 当前 turn 的输入（见 image-tools 的 `source_file_id`）|
| 产物 artifact | agent / 工具（`image_generate`、`tts_generate`）| 运行时能力 | 模型生成的图 / 音 |

> handler 产出的图（`ctx.image_generate` / `ctx.image_edit`）也能进本命名空间，有两条路、区别只在**何时落盘**：**A 即时**（`ctx.save_upload(content=, content_type=)`，生成即落，返回与下文同形的 `{url, resource_ref, …}`）或 **B 延迟提交**（handler 把字节返回前端，用户确认时再走本文的 `api/upload` 落盘——编辑期不产孤儿）。选型与代码见 [image-tools.md](image-tools.md) 的「把 handler 产出的图落进 uploads」。`ctx.read_upload(name)` 读回某个已登记上传的字节。

## 请求

`POST <preview-root>/api/upload` —— 用 `frontend-base` 的 `apiUrl('upload')` 自动拼当前 `/preview` 或 `/dev/preview` 前缀。

- `multipart/form-data`，单个 `file` 字段。
- **直接用 `fetch` + `FormData`，不要走 `lib/http.ts` 的 `request()`**——后者强制 `Content-Type: application/json`，会破坏 multipart 边界。让浏览器自动带 boundary（别手动设 `Content-Type`）。

允许格式（精确匹配；`;codecs=…` 参数会被忽略后再校验）：

| 类 | MIME |
|---|---|
| 图像 | `image/png` `image/jpeg` `image/webp` `image/gif` |
| 音频 | `audio/wav` `audio/webm` `audio/mp4` `audio/mpeg` `audio/ogg` |

- 浏览器 `MediaRecorder` 默认产 `audio/webm;codecs=opus`（Chrome/Firefox）或 `audio/mp4`（Safari），都被接受——**录音不用前端转码**。
- HTML / SVG / JS / PDF **一律拒**（415），避免同源 XSS。
- 超 `upload_max_bytes` → 413；空文件 → 400；上传到不存在的实例 → 404（上传必须发生在一个已存在的实例里，即至少跑过一次 turn）。

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
- **删除**：业务对象删除或换图后，先扫描完整实例确认资产已零引用，再调用 `ctx.delete_asset(upload_name=asset_id, purge_origin=True)`；失败会进入平台 GC。不要只删 URL 引用后留下孤儿，也不要在仍有其他引用时删物理文件。

## resource_ref 端到端

dsl_builder 不投影；也没有 `ctx.upload_url(resource_ref)` 这类 helper。投影发生在 Go 预览代理：FDA 返回 `api/dsl.json` / `api/<handler>` 的 JSON 后，Go 在鉴权通过的当前平面把对象里的 `resource_ref` 或 `resource_refs` 写回可访问 URL。

活动要做的是把 ref 放在"今天放媒体 URL 的那个对象"旁边，并使用可投影字段名。闭集是：

```text
read_url / file_url / image_url / thumbnail_url / audio_url / trace_url
```

最小配方：

1. SPA `POST api/upload` 后，把 `{resource_ref, url, page_index}` 发给业务 handler。
2. handler 把 `resource_ref` 存进 typed-KV；建议也存 `url` 作为调试兜底，但业务读取优先用 ref。
3. `dsl_builder` 原样带出一个媒体对象，字段名用上面的闭集之一，并把 `resource_ref` 放在同一个对象里。
4. SPA 最终通常收到已投影后的 URL 字符串；仍统一过 `resolveAssetUrl()`，这样 direct FDA mount 和 Go developer proxy 都能显示。

```python
# handlers.py：保存上传归属
def save_page_recording(page_index: int, resource_ref: dict, url: str = "") -> dict:
    data = ctx.get_data() or {}
    recordings = data.setdefault("recordings", {})
    recordings[str(page_index)] = {
        "resource_ref": resource_ref,
        "url": url,  # fallback only; do not parse
        "author_user_id": ctx.user_id,
    }
    ctx.set_data(data)
    ctx.notify_dsl_update()
    return {"ok": True}
```

```python
# dsl_builder.py：让 Go 有字段可写回
recording = data.get("recordings", {}).get(str(page_index), {})
audio = {
    "audio_url": recording.get("url", ""),
    "resource_ref": recording.get("resource_ref"),
}
```

如果同一个对象里有多个媒体字段且它们指向不同资源（例如 `image_url` 是图、`audio_url` 是朗读），FDA 的出站 walker 会产字段级 `resource_refs`，Go 逐字段投影，避免一个 ref 覆盖另一个字段。活动作者通常不用手写 `resource_refs`；只要 URL 字段名在闭集里，运行时会从 `/v1/...` 或 `/preview/.../uploads/...` 自动派生。

## 归属：平台不管业务

平台只**存字节 + 发 ref**。"谁传的、传给绘本第几页、是不是当前用户的录音"全是你的活动业务——在 handler 里用 `ctx.user_id`（Go 鉴权的可信用户，见 `api/whoami`）写进你自己的 `data.json`，和评论作者身份同一套。**upload 端点本身不记用户、不做归属、不做配额。**

`ctx.user_name`（`str | None`）是调用者的**显示名**，来自 `X-FDA-User-Name` 头（percent-decoded）。仅用于界面展示 / 署名（如 "某某上传了…"）；身份校验、归属鉴权、配额管理仍须用 `ctx.user_id`。该字段 best-effort，头缺席时为 `None`——使用前必须判空。

典型流：

1. SPA `POST api/upload` → 拿 `resource_ref` / `url`；
2. SPA `POST api/<your_handler>`（带上 url + 业务位置，如 `page_index`）；
3. handler 校验 `ctx.user_id` 后把 `resource_ref`（和可选 `url` 兜底）落进 `data.json`；
4. `dsl_builder` 渲染时带出同对象的 `audio_url` / `image_url` + `resource_ref`，SPA 用 `resolveAssetUrl()` 显示。

## 录音 → 克隆朗读

用户录的音可直接喂 `tts_generate(reference_audio=<上传返回的 url>, prompt_text=…)`（clone provider），让 agent 用用户的声音朗读。见 [tts-tools.md](tts-tools.md)。

# Reference — 图像生成 / 编辑工具

`image_generate`（文生图）与 `image_edit`（图生图 / 风格转换）是同一套图像 capability 的两个工具，共享存储 / 计费 / 配置层。

## Contents

- `image_generate`（签名 / 返回 / store）
- 产物如何展示给用户
- `ctx.image_generate` / `ctx.image_edit`（handler/SPA 直调 · `source_upload` 改上传图 · 落 uploads 两条路：A `save_upload` 即时 / B 返回字节延迟提交 · `read_upload`）
- `image_edit`（签名 / 返回 / 约束 / source 引用与安全）
- 实测工时 · Runtime 配置（env vars + 活动级覆盖）
- Skill 范式 · 计费 `image_bill` · 诊断与修法

> store 三档语义（`auto`/`oss`/`sandbox`、永不过期的 `/v1` 代理、WRONG/RIGHT、MinIO 配置）的**权威是 [store-mode-table.md](store-mode-table.md)**；本文只保留 image 工具特有的部分。

---

## `image_generate` 工具

## 启用方式

manifest.json 加 `capabilities: ["image_generate"]`。详见 [`policies/capabilities.md`](../policies/capabilities.md)。

---

## 工具签名

```python
result = image_generate(
    prompt: str,                # ≤500 chars
    size: str = "1920x1920",    # canonical "WxH"
    n: int = 1,                 # 1-4
    style: str | None = None,
    negative_prompt: str | None = None,
    seed: int | None = None,
    store: str | None = None,   # "auto" | "oss" | "sandbox"; defaults to IMAGE_GEN_DEFAULT_STORE
) -> dict
```

返回 dict 有两种形态：

**成功**：

```jsonc
{
  "artifacts": [
    {
      "artifact_id": "img-a1b2c3d4e5",
      "store": "oss",                   // or "sandbox"
      "file_url": "/v1/activity-types/<activity_type_id>/activities/<activity_id>/artifacts/img-xxx/content",  // 永远是 /v1 代理（durable）— 见 store-mode-table.md
      "sandbox_path": "/instance/artifacts/live/<turn>/img-xxx.png",  // present iff store=="sandbox"
      "storage_key": "activities/<activity_type_id>/<activity_id>/<turn>/img-xxx.png",     // oss only
      "mime_type": "image/png",
      "width": 1024,
      "height": 1024,
      "seed": 42,
      "revised_prompt": "<some providers rewrite the prompt; if so, it's here>"
    }
  ],
  "usage": {
    "provider": "wanxiang",
    "model": "wan2.7-image-pro",
    "image_count": 1,
    "size": "1024x1024",
    "duration_ms": 18345
  }
}
```

**失败**：

```jsonc
{ "error": "image generation timed out: ..." }
// or {"error": "image generation failed: RuntimeError: ..."}
// or {"error": "store='oss' requested but object storage is not configured"}
// or {"error": "n must be an integer 1-4 (got 7)"}
// or {"error": "per-turn image cap (4) would be exceeded ..."}
// or {"error": "prompt exceeds 500 chars (623 given)"}
// or {"error": "prompt must be a non-empty string"}
```

**On error: do NOT retry the same prompt**. The provider has already decided; identical retries waste tokens.

失败会回滚本次预留的 per-turn 配额（runtime `rollback_reserved()`）——失败**不占用** `IMAGE_GEN_MAX_PER_TURN` 名额，与 `tts_generate` 语义对称（见 [tts-tools.md](tts-tools.md)）。照常出卡、图片变量留空即可（`image` 块自动隐藏）。`image_edit` 与 `image_generate` 共享同一计数器，回滚语义相同。

---

## 存储模式选择 — `store=`

三档语义 / 选择规则 / 永不过期机制 → **[store-mode-table.md](store-mode-table.md)**。image 工具特有的两点：

- `auto` 的全局兜底值由 `IMAGE_GEN_DEFAULT_STORE` env 控制（部署级），活动每次调用可 override。
- `image_edit` 即使 `store="sandbox"` 也需要对象存储做 source staging（见下方"重要约束"）。

---

## 产物如何展示给用户

`image_generate` / `image_edit` 返回 `result["artifacts"][0]`，runtime 自动把它登记为 `ActivityAgentOutput.artifacts[]`；活动**不调** `artifact_emit`。卡片展示**统一用 `file_url`**——两种 store 它都是 `/v1/.../content` 代理（oss 每次现签、永不过期；sandbox 服务本地字节），不必按 store 分支、不要自己拼桶 URL。

ImageBlock 模板：

```jsonc
card.blocks: [{
  "type": "image",
  "images": [{
    "read_url": img["file_url"],
    "title": "<caption>",
    "description": "<desc>"
  }]
}]
```

---

## Static Preview / SPA 图像按钮（`ctx.image_generate` / `ctx.image_edit`）

活动有 `site/` 时，让前端**直接触发生图 / 改图**（点按钮即时预览）走 handler，不要为此发一轮 turn——交给 agent turn 等于让模型"自己决定"调不调，按钮语义不确定。做法与 [tts-tools.md](tts-tools.md) 的喇叭按钮一致。

声明对应 capability 后，传给 `make_handlers(ctx)` / `make_tools(ctx)` 的 ctx 上会多出 helper，**与同名 turn 工具同参数、同返回**：

| capability | ctx helper | 用途 |
|---|---|---|
| `image_generate` | `ctx.image_generate(...)` | 文生图（如按用户文字配图）|
| `image_edit` | `ctx.image_edit(...)` | 图生图 / 改图（如修复用户在预览页上传的老照片）|

> 计费与归因由平台自动处理，活动无需关心。

1. `manifest.json` 同时声明：

```jsonc
{
  "capabilities": ["image_generate"],
  "handlers_module": "handlers"
}
```

2. `handlers.py` 里调用（判空 → 调用 → 取 `file_url`，失败回 envelope 不抛）：

```python
def make_handlers(ctx):
    def generate_illustration(prompt: str = "") -> dict:
        text = (prompt or "").strip()
        if not text:
            return {"ok": False, "error": "prompt is required"}
        gen = getattr(ctx, "image_generate", None)
        if gen is None:            # capability 未启用 → 优雅降级
            return {"ok": False, "error": "image generation unavailable"}
        result = gen(prompt=text[:500], size="1920x1920", n=1, store="auto")
        if not isinstance(result, dict) or result.get("error"):
            return {"ok": False, "error": (result or {}).get("error", "image failed")}
        artifacts = result.get("artifacts") or []
        image_url = (artifacts[0].get("file_url") if artifacts else "") or ""
        # 把图写进 typed-KV（让它持久进 DSL）时：改完业务数据后调一次 ctx.notify_dsl_update()
        return {"ok": bool(image_url), "image_url": image_url,
                "error": "" if image_url else "image returned no artifact"}

    return {"generate_illustration": generate_illustration}
```

完整范例见「婚礼爱情档案」的 `image_helpers.py:generate_preview_image`（被 `generate_memory_record` / `generate_comic_chapter` handler 调用：文+图组合、写 typed-KV 后 `notify_dsl_update`）。

3. 前端 POST 当前 preview 根路径下的 `api/<handler>`，用 `frontend-base/src/lib/api-base.ts` 的 `apiUrl('generate_illustration')`（或活动自己的 `apiCall` 封装）。**直接使用返回的 `image_url`**（`<img src={url}>`）——不要硬编码 `/v1/...`、也不要自己拼 URL，平台会让它在当前预览环境下可访问。

> **约束**：每次 handler 调用累计最多 `IMAGE_GEN_MAX_PER_TURN` 张（generate + edit 共享），失败不占名额；超出额度时返回 `{"error": ...}`，照常优雅降级即可。

### 改图：编辑用户在预览页上传的照片（`ctx.image_edit` + `source_upload`）

让用户在预览页传一张照片、再点"修复 / 改图"：先 `POST api/upload` 拿到上传名（url 末段 `<sha>.<ext>`），作为 `source_upload` 传给 `ctx.image_edit` 即可——`source_upload` 是 image_edit 专指**预览页上传产物**的 source（见下文 source 表）。

```python
def make_handlers(ctx):
    def restore_photo(upload: str = "") -> dict:
        edit = getattr(ctx, "image_edit", None)
        if edit is None:
            return {"ok": False, "error": "image edit unavailable"}
        name = upload.rstrip("/").split("/")[-1].split("?")[0]   # url → <sha>.<ext>
        res = edit(source_upload=name, prompt="修复这张老照片：去噪、修补、增强清晰度，保持原貌", store="auto")
        if not isinstance(res, dict) or res.get("error"):
            return {"ok": False, "error": (res or {}).get("error", "edit failed")}
        arts = res.get("artifacts") or []
        return {"ok": bool(arts), "image_url": (arts[0].get("file_url") if arts else "")}
    return {"restore_photo": restore_photo}
```

### 把 handler 产出的图落进 uploads —— 两条路，按交互模型选

`image_generate` / `image_edit` 的产物是 **artifact**（`file_url` 指向 `/v1/.../artifacts/...`）。要让它成为活动自己的"一张照片"（喂进加照片数据流、和用户上传同命名空间、复用上传生命周期），有两条路，**区别只在字节什么时候落盘**——按交互模型选，平台两条都支持：

| | **A · 即时落盘**（`ctx.save_upload`）| **B · 延迟提交**（返回字节 → 前端确认时 `api/upload`）|
|---|---|---|
| 落盘时机 | handler 内、生成即落 | 用户在前端**确认**时才落 |
| handler 返回给前端 | 一个 uploads URL（可直接拿去 add_memory）| 图片**字节**（如 base64 data URL），**不**落盘 |
| 预览来源 | 返回的 URL（经服务端取图）| 本地字节（object-URL / data URL），不依赖服务端取图 |
| 丢弃 / 反复重生成的图 | 也会落盘（孤儿清理归活动）| **永不落盘**（不产孤儿）|
| 典型场景 | 生成即定稿；agent / 非交互流程；想一步到位 | 交互式编辑器：用户可能反复改或丢弃，确认前都算草稿 |

> 两条路终点相同：同一个 uploads 命名空间、同形 `{url, resource_ref}`（A 经 `ctx.save_upload`，B 经 [user-upload.md](user-upload.md) 的 `api/upload`）；之后都当普通上传引用，显示走 `resolveAssetUrl()`（要同源拉字节加 `?proxy=true`）。

**A — `ctx.save_upload`（即时落盘）**

```python
# store="sandbox" 让产物落到本地，便于读回字节
res = ctx.image_edit(source_upload=name, prompt="…", store="sandbox")
art = (res.get("artifacts") or [None])[0]
from pathlib import Path
data = (Path(ctx.instance_dir) / art["sandbox_path"].removeprefix("/instance/")).read_bytes()
saved = ctx.save_upload(content=data, content_type=art["mime_type"])
# saved["url"] 形如 <preview-root>/uploads/<name>，与 api/upload 返回同形 —— 之后当普通上传引用
```

| helper | 签名 | 返回 |
|---|---|---|
| `ctx.save_upload` | `(*, content: bytes, content_type: str)` | `{url, upload_name, resource_ref, content_type, byte_size, sha256}`（与 `POST api/upload` 同形）|
| `ctx.read_upload` | `(upload_name: str) -> bytes \| None` | 读回一个已登记上传的字节；未登记 / 不可读 → `None` |

> 两个 helper 在平台 `storage` 就绪时即可用（不需要额外 capability）；允许的 `content_type` 与 `api/upload` 一致（图像 + wav）。

**B — 返回字节，前端确认时才落盘**

```python
# handler：生成到 sandbox、读回字节，作为 data URL 返回（不写 uploads）
import base64
from pathlib import Path
res = ctx.image_generate(prompt="…", store="sandbox")
art = (res.get("artifacts") or [None])[0]
data = (Path(ctx.instance_dir) / art["sandbox_path"].removeprefix("/instance/")).read_bytes()
return {"ok": True, "data_url": f"data:{art['mime_type']};base64," + base64.b64encode(data).decode("ascii")}
```

前端拿 `data_url` 本地预览；用户**确认**时把这坨字节（或用户自己选的 `File`）`POST api/upload`（`apiUrl('upload')`）拿到 uploads URL，再写业务数据。纯"用户选图"场景同理——`File` 一直留在页面，确认才上传，handler 都不用碰图字节。

> 落盘只发生在确认那一下，所以编辑期是纯页面草稿：换图 / 重生成 / 放弃都不触碰存储；预览用本地字节，也不经服务端取图。上传命名空间的语义见 [user-upload.md](user-upload.md)。

---

## `image_edit` 工具

### 启用方式

manifest.json 加 `capabilities: ["image_edit"]`。可以与 `"image_generate"` 同时声明（两者共享同一 wanxiang provider 实例 + 同一个 `IMAGE_GEN_MAX_PER_TURN` per-turn 计数器）。

### 工具签名

```python
result = image_edit(
    prompt: str,                     # ≤500 chars，描述要怎么改（多图时用 图1/图2 指代）
    sources: list[str] | None = None,# 多图：有序引用列表，图1=sources[0] 图2=sources[1]…（与下面 4 个单数参数互斥）
    source_artifact_id: str | None = None,
    source_file_id: str | None = None,
    source_path: str | None = None,
    source_url: str | None = None,
    source_upload: str | None = None,# 预览页上传产物（POST api/upload 的名字 <sha>.<ext>，或其 url）
    size: str = "1024x1024",
    strength: float = 0.7,           # 0.0=接近原图 / 1.0=大幅改造（wanxiang 当前忽略；保留接口为未来 provider 准备）
    style: str | None = None,
    seed: int | None = None,
    store: str | None = None,        # "auto" | "oss" | "sandbox"
) -> dict
```

**source 二选一**：要么传 `sources`（多图，1..N 张有序引用），要么传 4 个单数 `source_*` 参数中**恰好 1 个**——两条路径整体互斥。单数路径由 `resolver.resolve()` 解析、`sources` 路径由 `resolver.resolve_many()` 解析，都返回 bytes。`sources` 是**有序**的：模型按位置把它们认作 图1 / 图2 / …，所以 prompt 里的序号指代必须跟列表顺序一致（融合 / 多参考 / 局部编辑全靠 prompt 表达，wan2.x 不需要 mask 或角色字段）。最多 `IMAGE_EDIT_MAX_SOURCES` 张（默认 5）。

### 成功返回

```jsonc
{
  "artifacts": [{
    "artifact_id": "img-...",
    "store": "oss",                    // or "sandbox"
    "file_url": "/v1/activity-types/<activity_type_id>/activities/<activity_id>/artifacts/img-.../content",  // 永远是 /v1 代理（durable）— 见 store-mode-table.md
    "sandbox_path": "/instance/...png",      // when store==sandbox
    "storage_key": "activities/.../...png",  // oss only
    "mime_type": "image/png",
    "width": 1024, "height": 1024,           // 真实尺寸（万相 edit 通常跟源图同尺寸）
    "seed": null,
    "revised_prompt": null,
    "source_kind": "file",             // 主 source 类型（多图时=第一张；"artifact" / "file" / "sandbox" / "url"）
    "source_ref": "file_0",            // 主 source 原始引用值（id / path / url）— 用于 audit
    "source_kinds": ["file", "url"],   // 仅多图（len(sources)>1）时出现：各 source 类型，按 图1/图2 顺序
    "source_refs": ["file_0", "https://…"]  // 仅多图时出现：各 source 原始引用值，顺序对应
  }],
  "usage": {"provider":"wanxiang","model":"wan2.7-image-pro","image_count":1,"duration_ms":17297,"size":"1024x1024"}
}
```

### 失败返回

```jsonc
{ "error": "source resolution failed: artifact 'img-xxx' not found: ..." }
// or {"error": "image edit timed out: ..."}
// or {"error": "image edit failed: RuntimeError: <wanxiang FAILED reason>"}
// or {"error": "image_edit requires object storage for source staging ..."}
// or {"error": "strength must be in 0.0-1.0 (got 1.5)"}
// or {"error": "per-turn image cap (4) would be exceeded ..."}
// or {"error": "too many source images: 7 given (max 5)"}                         // sources 超过 IMAGE_EDIT_MAX_SOURCES
// or {"error": "pass either `sources` (multi-image) or a single legacy source param — not both (...)"}
```

**On error: do NOT retry the same source + prompt** — provider already decided.

### 重要约束

- **必须配置 object storage**：wanxiang 要图 URL 不要 bytes，runtime 把 source bytes stage 到对象存储（key 前缀 `image-edit-sources/`）拿 URL 喂给 provider。即使 `store="sandbox"` 也需要对象存储做 staging
- **size 是 hint 不是承诺**：万相通常返回跟源图同尺寸
- **strength 当前被 wanxiang 忽略**：保留接口位置给未来 provider（SDXL / Imagen 等）
- **per-turn cap 跟 image_generate 共享**：单 turn 内 generate + edit 累计 ≤ `IMAGE_GEN_MAX_PER_TURN`
- **多图输入**：`sources` 最多 `IMAGE_EDIT_MAX_SOURCES` 张（默认 5，模型上限 9）；**每一张**各自受 `IMAGE_EDIT_MAX_SOURCE_BYTES` 字节上限与同一套 SSRF / 路径穿越 / allowlist 检查；列表顺序 = prompt 里的 图1/图2。计费仍按**产出**张数（输入图数不计费）

---

## Image Source 引用方式（`image_edit`）

`image_edit` 接受 **6 种引用方式**：5 个单数参数（单图，互相互斥）+ `sources`（多图，有序列表）。`sources` 与 5 个单数参数**整体互斥**（传了 `sources` 就不能再传任何单数参数）。

| 参数 | 含义 | 何时用 |
|---|---|---|
| `sources` | 有序引用列表 `list[str]`；每项自动按前缀识别为 artifact id（`img-…`）/ file id（`file_…`）/ sandbox 路径（`/instance/…`）/ http(s) URL，可混用 | 要 2+ 张图（融合 / 多参考 / 把 A 放进 B）；列表顺序 = 图1/图2，与 prompt 序号对齐 |
| `source_artifact_id` | 当前 instance 内已 commit 的 OutputArtifact id（如 `img-d4c318b7ee`）| 在前面 turn 生成过的图，想接着改 |
| `source_file_id` | 当前 turn 用户上传文件的 `file_id`（如 `file_0`）| 用户传了照片 |
| `source_path` | sandbox 虚拟路径 `/instance/...` | 罕用；优先用前两种 |
| `source_url` | http(s) URL（受 allowlist 约束）| 用户给了公共 URL |
| `source_upload` | 预览页上传产物的名字（`POST api/upload` 返回 url 的末段 `<sha>.<ext>`，或整条 url）| 终端用户在**预览页**传的照片想直接改（如「修复老照片」按钮）；handler 路径首选 |

> `sources`（多图）只按前缀自动识别 artifact / file / sandbox / url 四类，**不含 upload**；要改预览页上传的图用单数 `source_upload`。

### 安全设计

- **sandbox path traversal**：必须以 `/instance/` 开头，canonicalize 后还在 `instance_dir` 下，否则 `ImageSourceError`
- **URL allowlist（default deny）**：`IMAGE_EDIT_URL_ALLOWLIST` **空 = 禁用 url source**（报 "url access is disabled"）；设了则按 **hostname 精确匹配**（大小写不敏感）放行，并附 DNS 解析 + 私网 IP 防护。不是前缀匹配
- **大小硬上限**：`IMAGE_EDIT_MAX_SOURCE_BYTES`（默认 10 MB）所有 source 类型都强制
- **mime 检测靠 magic bytes**，不信任 provider 返回的 `Content-Type`

### Skill 引导 LLM 怎么选 source

简化建议（单图"主参考图 + image_edit"流水线；多图见首个分支）：

```
if 需要把多张图合成一张（融合 / 多参考 / 把 A 放进 B）:
    use sources = [ref1, ref2, …]   # 有序；prompt 用 图1/图2 指代，与列表顺序一致
                                     # 每项可为 artifact_id / file_id / sandbox 路径 / URL，混用也行
elif user uploaded a file this turn:
    use source_file_id = files[0].file_id
elif user 引用 "the previous picture":
    look up the latest OutputArtifact with mime_type="image/*"
    use source_artifact_id = that artifact_id
elif user gave a URL:
    use source_url = the URL
else:
    emit intake card asking for source
```

---

## 实测工时（用来定 timeout）

| 调用 | 万相实测 | 计费 |
|---|---|---|
| `image_generate` 单张 1024x1024 | 15-40s | 1 张 |
| `image_generate` 单张 1280x1280 | 30-90s | 1 张 |
| `image_generate` 4 张 1024x1024 一次 | 40-120s | 4 张 |
| `image_edit` 单张 1024x1024 | 15-25s | 1 张 |

`IMAGE_GEN_TIMEOUT=120`、`IMAGE_EDIT_TIMEOUT=180` 已经覆盖正常上限。

---

## Runtime 配置（env vars）

| 变量 | 默认 | 含义 |
|---|---|---|
| `IMAGE_GEN_ENABLED` | `true` | 项目级开关；`false` 时所有图像工具静默缺席（即使活动声明 capability）|
| `IMAGE_GEN_PROVIDER` | `wanxiang` | 目前只有 wanxiang 接入 |
| `IMAGE_GEN_MODEL` | `wan2.7-image-pro` | 文生图模型 |
| `IMAGE_GEN_TIMEOUT` | `120` | 文生图单次调用秒数上限 |
| `IMAGE_GEN_DEFAULT_SIZE` | `1920x1920` | canonical "WxH"；adapter 转换格式 |
| `IMAGE_GEN_MAX_PER_TURN` | `4` | 单 turn 累计图像张数硬上限（generate + edit 共享）|
| `IMAGE_GEN_DEFAULT_STORE` | `auto` | 当活动不传 store 时用什么 |
| `IMAGE_EDIT_MODEL` | `wan2.7-image-pro` | 图像编辑模型 |
| `IMAGE_EDIT_TIMEOUT` | `180` | 编辑单次调用秒数上限 |
| `IMAGE_EDIT_MAX_SOURCE_BYTES` | `10485760` | 单张源图最大字节（10 MB）；多图时**每张**各自适用 |
| `IMAGE_EDIT_MAX_SOURCES` | `5` | 单次 edit 最多输入图数（有序 图1,图2…）；`1`=仅单图。模型上限 9 |
| `IMAGE_EDIT_URL_ALLOWLIST` | (空) | hostname 精确白名单（逗号分隔）；**空 = 禁用 url source**（default deny），非空才按 host 放行 |

provider 自身的 API key（如 `DASHSCOPE_API_KEY`）必须在环境里，否则 factory 返回 None → 工具不注入 → trace `capability_unavailable`。

### 活动级模型覆盖（runtime.json）

每个活动可以在 `activities/<id>/runtime.json` 里覆盖 `IMAGE_GEN_MODEL` / `IMAGE_EDIT_MODEL`：

```json
{
  "image_generate_model": "wan2.7-image-pro",
  "image_edit_model": "wan2.7-image-pro"
}
```

留空（不写）= 用环境变量给的全局默认。

**模型即后端**：填 Wanxiang 模型（`wan2.x-*`）走通义万相；填 Doubao/Seedream 模型（`doubao-seedream-*`）走火山引擎方舟——平台**按模型名自动路由**到对应后端，活动只挑模型，不配 provider、不碰 key。generate 与 edit（图生图）都按各自的模型字段路由。

```json
{
  "image_generate_model": "doubao-seedream-5-0-260128",
  "image_edit_model": "doubao-seedream-5-0-260128"
}
```

> 注：Seedream 倾向更大尺寸（如 `2K`/2048²）。若生图报尺寸错误，在 `image_generate(size=...)` 里传更大的 `size`。各后端凭证由平台/运维在服务端配置，活动无感。

---

## Skill 范式

活动 host SKILL.md 写一段 tool fast path 即可（形态见下方"最小活动模板"）。工具 docstring 已经被 `@tool(parse_docstring=True)` 自动注入 system prompt，SKILL.md 只引用工具签名即可，不必复制 docstring。

最小活动模板：

```md
## image_generate fast path

result = image_generate(prompt="<≤500 chars>", size="1920x1920", store="<auto|oss|sandbox>")

# 成功 → 把 result["artifacts"][0]["file_url"] 填进 card_emit_template 的 image 变量；
#         artifact 本身由 runtime 的 live-artifact pipeline 自动 surface（无需 artifact_emit）。
# 失败 (result has "error") → 用 card_emit_template 发错误卡并停（同 prompt 不重试）
```

---

## 计费 `image_bill` SSE 字段

成功的图像调用记录在 SSE done event payload 的 `image_bill` 字段，平行 `llm_bill`。每条 entry 带 `kind` 字段（`generate` / `edit`）区分调用类型：

```jsonc
"image_bill": {
  "calls": [
    { "seq": 1, "kind": "generate", "provider": "wanxiang", "model": "wan2.7-image-pro",
      "image_count": 1, "size": "1024x1024",
      "duration_ms": 29642, "ts": "2026-05-12T..." },
    { "seq": 2, "kind": "edit", "provider": "wanxiang", "model": "wan2.7-image-pro",
      "image_count": 1, "size": "1024x1024",
      "duration_ms": 17297, "ts": "2026-05-12T..." }
  ],
  "totals": {
    "calls": 2,
    "images": 2,
    "by_size": { "1024x1024": 2 },
    "generate_calls": 1,
    "edit_calls": 1,
    "duration_ms": 46939
  }
}
```

每次调用记录**尺寸 `size` + 张数 `image_count`**;`totals.by_size` 把张数**按尺寸汇总**(如 `{"1024x1024":3,"1280x1280":1}`),方便按尺寸定价时直接 `count×rate`。

**只记成功**。失败通过 `trace.jsonl` 的 `image_gen_failed` / `image_edit_failed` 事件审计,不进入 `image_bill`。

前端兼容性:现有读取 `image_bill.totals.images` 不变;`by_size` / `kind` / `generate_calls` / `edit_calls` 都是加性字段。

无 image 调用的 turn 完全不出现 `image_bill` 键。

**持久化**:平台把每轮账单写入成本台账(`activity_cost_ledger`):扁平列 `image_count`(张数)用于聚合;完整明细(含 `by_size`)存 `bill_detail`(jsonb)列,不丢尺寸信息。

---

## 诊断与修法

| 症状 | 修法 |
|---|---|
| 工具返 `{"error":...}` | emit 错误卡（`card_emit_template`）并停；同 prompt 不重试 |
| 卡片展示用哪个字段 | 统一用 `file_url`（见上方"产物如何展示"）；`sandbox_path` 仅供同 turn 内传给 `image_edit` 上游 |
| 卡片渲染丢图（oss 模式） | OutputArtifact 用 `url=` 字段填，不要用 `path=`（同时存在时 path 优先，URL 被丢） |
| 出图质量差 | prompt 具体化：主体、风格、光线、调色，每项一句 |
| `image_edit` 报 `exactly one of artifact_id / file_id / path / url required` | 单图路径：4 个单数 source 参数恰传 1 个（多图改用 `sources`）|
| `image_edit` 报 `too many source images: N given (max M)` | `sources` 超过 `IMAGE_EDIT_MAX_SOURCES`；减少图数或调大该 env |
| `image_edit` 报 `pass either sources … not both` | `sources` 与单数 `source_*` 同时传了；二选一 |
| 多图融合没认对"图1/图2" | prompt 序号要跟 `sources` 列表顺序一致；明确写"图1的X、图2的Y" |
| `image_edit` 报 `requires object storage for source staging` | 配置对象存储（`OBJECT_STORAGE_PROVIDER` + `MINIO_*`/`S3_*`）；或活动 manifest 不声明 `image_edit` capability |
| `image_edit` 报 `sandbox path escapes instance directory` | `source_path` 落在 `/instance/` 下且 canonicalize 不逃逸 |
| 用户上传图的最稳引用 | 用 `source_file_id="file_0"`（runtime 直接 lookup），不要自己拼 `/instance/turns/.../files/xxx.jpg` |
| `metadata` 字段传图片字节 | 前端不解析；走 OutputArtifact `kind=file` |
| host SKILL.md 重复了工具 docstring | 删掉重复段落；`@tool(parse_docstring=True)` 已经把 docstring 注入 system prompt |

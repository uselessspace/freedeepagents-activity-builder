# Reference — 图像生成 / 编辑工具

`image_generate`（文生图）与 `image_edit`（图生图 / 风格转换）是同一套图像 capability 的两个工具，共享存储 / 计费 / 配置层。

## Contents

- `image_generate`（签名 / 返回 / store）
- 产物如何展示给用户
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
    size: str = "1024x1024",    # canonical "WxH"
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

## `image_edit` 工具

### 启用方式

manifest.json 加 `capabilities: ["image_edit"]`。可以与 `"image_generate"` 同时声明（两者共享同一 wanxiang provider 实例 + 同一个 `IMAGE_GEN_MAX_PER_TURN` per-turn 计数器）。

### 工具签名

```python
result = image_edit(
    prompt: str,                     # ≤500 chars，描述要怎么改
    source_artifact_id: str | None = None,
    source_file_id: str | None = None,
    source_path: str | None = None,
    source_url: str | None = None,
    size: str = "1024x1024",
    strength: float = 0.7,           # 0.0=接近原图 / 1.0=大幅改造（wanxiang 当前忽略；保留接口为未来 provider 准备）
    style: str | None = None,
    seed: int | None = None,
    store: str | None = None,        # "auto" | "oss" | "sandbox"
) -> dict
```

**`source_*` 4 个参数恰必传 1 个**（互斥），由 `ImageSourceResolver` 解析成 bytes。

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
    "source_kind": "file",             // 哪种 source 类型（"artifact" / "file" / "sandbox" / "url"）
    "source_ref": "file_0"             // 原始引用值（id / path / url）— 用于 audit
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
```

**On error: do NOT retry the same source + prompt** — provider already decided.

### 重要约束

- **必须配置 object storage**：wanxiang 要图 URL 不要 bytes，runtime 把 source bytes stage 到对象存储（key 前缀 `image-edit-sources/`）拿 URL 喂给 provider。即使 `store="sandbox"` 也需要对象存储做 staging
- **size 是 hint 不是承诺**：万相通常返回跟源图同尺寸
- **strength 当前被 wanxiang 忽略**：保留接口位置给未来 provider（SDXL / Imagen 等）
- **per-turn cap 跟 image_generate 共享**：单 turn 内 generate + edit 累计 ≤ `IMAGE_GEN_MAX_PER_TURN`

---

## Image Source 引用方式（`image_edit`）

`image_edit` 工具接受 4 种互斥 source：

| 参数 | 含义 | 何时用 |
|---|---|---|
| `source_artifact_id` | 当前 instance 内已 commit 的 OutputArtifact id（如 `img-d4c318b7ee`）| 在前面 turn 生成过的图，想接着改 |
| `source_file_id` | 当前 turn 用户上传文件的 `file_id`（如 `file_0`）| 用户传了照片 |
| `source_path` | sandbox 虚拟路径 `/instance/...` | 罕用；优先用前两种 |
| `source_url` | http(s) URL（受 allowlist 约束）| 用户给了公共 URL |

### 安全设计

- **sandbox path traversal**：必须以 `/instance/` 开头，canonicalize 后还在 `instance_dir` 下，否则 `ImageSourceError`
- **URL allowlist（default deny）**：`IMAGE_EDIT_URL_ALLOWLIST` **空 = 禁用 url source**（报 "url access is disabled"）；设了则按 **hostname 精确匹配**（大小写不敏感）放行，并附 DNS 解析 + 私网 IP 防护。不是前缀匹配
- **大小硬上限**：`IMAGE_EDIT_MAX_SOURCE_BYTES`（默认 10 MB）所有 source 类型都强制
- **mime 检测靠 magic bytes**，不信任 provider 返回的 `Content-Type`

### Skill 引导 LLM 怎么选 source

简化建议（"主参考图 + image_edit"流水线）：

```
if user uploaded a file this turn:
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
| `IMAGE_GEN_DEFAULT_SIZE` | `1024x1024` | canonical "WxH"；adapter 转换格式 |
| `IMAGE_GEN_MAX_PER_TURN` | `4` | 单 turn 累计图像张数硬上限（generate + edit 共享）|
| `IMAGE_GEN_DEFAULT_STORE` | `auto` | 当活动不传 store 时用什么 |
| `IMAGE_EDIT_MODEL` | `wan2.7-image-pro` | 图像编辑模型 |
| `IMAGE_EDIT_TIMEOUT` | `180` | 编辑单次调用秒数上限 |
| `IMAGE_EDIT_MAX_SOURCE_BYTES` | `10485760` | 源图最大字节（10 MB） |
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

留空（不写）= 用环境变量给的全局默认。provider 本身（wanxiang）不可在活动层覆盖——目前只接入一家，凭证 + adapter 仍是全局单例。

---

## Skill 范式

活动 host SKILL.md 写一段 tool fast path 即可（形态见下方"最小活动模板"）。工具 docstring 已经被 `@tool(parse_docstring=True)` 自动注入 system prompt，SKILL.md 只引用工具签名即可，不必复制 docstring。

最小活动模板：

```md
## image_generate fast path

result = image_generate(prompt="<≤500 chars>", size="1024x1024", store="<auto|oss|sandbox>")

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
| `image_edit` 报 `exactly one of artifact_id / file_id / path / url required` | source 参数恰传 1 个 |
| `image_edit` 报 `requires object storage for source staging` | 配置对象存储（`OBJECT_STORAGE_PROVIDER` + `MINIO_*`/`S3_*`）；或活动 manifest 不声明 `image_edit` capability |
| `image_edit` 报 `sandbox path escapes instance directory` | `source_path` 落在 `/instance/` 下且 canonicalize 不逃逸 |
| 用户上传图的最稳引用 | 用 `source_file_id="file_0"`（runtime 直接 lookup），不要自己拼 `/instance/turns/.../files/xxx.jpg` |
| `metadata` 字段传图片字节 | 前端不解析；走 OutputArtifact `kind=file` |
| host SKILL.md 重复了工具 docstring | 删掉重复段落；`@tool(parse_docstring=True)` 已经把 docstring 注入 system prompt |

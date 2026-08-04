# Image store mode quick reference

`image_generate(store=...)` / `image_edit(store=...)` decides where bytes land.

| store | Backed by | OutputArtifact shape | When to pick |
|---|---|---|---|
| `auto` (default) | Go managed asset storage when configured, otherwise instance-local artifact storage | `file_url` + `resource_ref`; placement-specific fields may also appear | Most activity code |
| `oss` | Go managed asset storage (no FDA-local copy) | `file_url` + `resource_ref` + `asset_id` | Only when remote placement is an explicit deployment requirement |
| `sandbox` | instance-local `artifacts/<turn_id>/` storage | `file_url` + `resource_ref` + `sandbox_path` | Local/private placement; still registered for cross-turn artifact lookup |

> **`oss` is the provider-neutral store keyword.** The backend implementation is chosen by `OBJECT_STORAGE_PROVIDER` (`minio` / `s3` …) + the matching `MINIO_*` env — `oss` just means "upload to object storage", not a specific vendor (MinIO / Aliyun OSS / S3 / Qiniu all qualify).

> **Managed mode has no FDA-local copy.** Production stores an opaque
> `asset_id`; Go's asset control plane owns physical placement, signed reads,
> billing and deletion. Activity code keeps `resource_ref` for identity and
> uses the returned `file_url` only as an opaque render URL. Never persist a
> provider bucket key or construct a storage URL.

## Selection rules

| Scenario | Recommended input |
|---|---|
| Reference for later `image_edit` | Persist `artifact_id` / `resource_ref`; both managed and instance-local artifacts support cross-turn lookup |
| Frontend renders the image | Use returned `file_url` or projected `resource_ref`; do not branch on store |
| Deployment explicitly requires remote managed placement | request `store="oss"`; otherwise leave `store` unset (`auto`) |

## Two shapes, don't confuse them

- **What the tool returns** (`result["artifacts"][0]`): `artifact_id` /
  `resource_ref` / `file_url` / optional `asset_id` or `sandbox_path` / `store`
  / `width` / `height` … — the side-channel data the
  LLM reads to decide what to put in a card. Full field list:
  [image-tools.md](image-tools.md) §产物如何展示.
- **OutputArtifact** (what lands in `ActivityAgentOutput.artifacts[]`): a
  StrictModel with exactly `artifact_id` / `kind` / `title` / `path` / `content`
  / `mime_type` / `description` / `url` (`additionalProperties:false`; required:
  `artifact_id` + `kind` + `title`; one of path/content/url). `read_url` /
  `resource_ref` / `asset_id` are tool/persisted-record fields, **not**
  `OutputArtifact` authoring fields. For images you usually don't
  build an OutputArtifact by hand at all — the runtime live-artifact pipeline
  surfaces it; you just put `file_url` into the card. Schema:
  [card-block-types.md](card-block-types.md) §OutputArtifact.

## Persist identity, not placement details

When you need a reference image across turns, persist `artifact_id` and preferably
the returned `resource_ref`. A `file_url` may be kept as a display fallback, but
never persist `sandbox_path`, `asset_id`, a bucket key, or a presigned provider URL:

```python
# WRONG — placement-specific virtual path
set_reference(url="/instance/artifacts/live/<turn>/img-xxx.png")
# WRONG — a baked-in presigned bucket URL expires
set_reference(url="https://oss.example/.../img-xxx.png?X-Amz-...")
# RIGHT — stable runtime identity; optional opaque render URL
set_reference(
    artifact_id=result["artifacts"][0]["artifact_id"],
    resource_ref=result["artifacts"][0]["resource_ref"],
    url=result["artifacts"][0]["file_url"],
)
```

## What if object storage isn't set up?

In dev environments without an object store:
- `store=auto` falls back to sandbox transparently
- `store=oss` fails loudly: `{"error": "store='oss' requested but object storage is not configured"}`

Set up MinIO (the default S3-compatible backend) in dev to match production:
```bash
docker run -d -p 9000:9000 -p 9001:9001 minio/minio server /data --console-address :9001
# then in .env: OBJECT_STORAGE_PROVIDER=minio + MINIO_ENDPOINT / MINIO_ACCESS_KEY / MINIO_SECRET_KEY / MINIO_BUCKET
```

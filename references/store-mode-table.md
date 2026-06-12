# Image store mode quick reference

`image_generate(store=...)` / `image_edit(store=...)` decides where bytes land.

| store | Backed by | OutputArtifact shape | When to pick |
|---|---|---|---|
| `auto` (default) | object storage if configured else sandbox | tool returns a `file_url` either way | Most cases; uncertain |
| `oss` | object storage (no local copy) | tool returns `file_url` (durable /v1 proxy) + `storage_key` | locked-reference flows, frontend `<img src=...>`, image_edit source |
| `sandbox` | container `/instance/artifacts/live/<turn_id>/` | tool returns a `sandbox_path` | One-turn intermediate; not reused |

> **`oss` is the provider-neutral store keyword.** The backend implementation is chosen by `OBJECT_STORAGE_PROVIDER` (`minio` / `s3` …) + the matching `MINIO_*` env — `oss` just means "upload to object storage", not a specific vendor (MinIO / Aliyun OSS / S3 / Qiniu all qualify).

> **OSS-mode artifacts keep NO local copy.** With `store="oss"` the bytes live only in object storage; the runtime records a `storage_key` on the artifact (no local file). The returned `file_url` is the platform's `/v1/.../artifacts/<id>/content` **proxy** (NOT the direct bucket URL): on each request the platform re-signs the bucket URL from `storage_key` and **302-redirects**. So a card storing this `file_url` **never rots** — whereas a baked-in presigned bucket URL expires (and a public one 403s on a private bucket). Always embed `file_url` as-is; never hand-build a bucket URL.

## Hard rules

| Scenario | Required store |
|---|---|
| `image_axis = generate+edit-locked` (reference for later edits) | **`oss`** (sandbox path dies on container restart) |
| Frontend will `fetch()` the image | **`oss`** |
| Image is given to another `image_edit` as `source_url=` | **`oss`** |

## Two shapes, don't confuse them

- **What the tool returns** (`result["artifacts"][0]`): `file_url` / `sandbox_path`
  / `storage_key` / `store` / `width` / `height` … — the side-channel data the
  LLM reads to decide what to put in a card. Full field list:
  [image-tools.md](image-tools.md) §产物如何展示.
- **OutputArtifact** (what lands in `ActivityAgentOutput.artifacts[]`): a
  StrictModel with exactly `artifact_id` / `kind` / `title` / `path` / `content`
  / `mime_type` / `description` / `url` (`additionalProperties:false`; required:
  `artifact_id` + `kind` + `title`; one of path/content/url). `read_url` /
  `storage_key` are **not** OutputArtifact fields. For images you usually don't
  build an OutputArtifact by hand at all — the runtime live-artifact pipeline
  surfaces it; you just put `file_url` into the card. Schema:
  [card-block-types.md](card-block-types.md) §OutputArtifact.

## Don't persist a sandbox path or a presigned bucket URL in typed-KV

When you need to remember a reference image across turns, write the **durable
`/v1` proxy URL** (or just the `artifact_id`) via an activity @tool / `data_set` —
never the sandbox path (dies on container restart) or a raw presigned bucket URL
(expires; 403s on a private bucket):

```python
# WRONG — sandbox path dies when the container restarts
set_reference(url="/instance/artifacts/live/<turn>/img-xxx.png")
# WRONG — a baked-in presigned bucket URL expires
set_reference(url="https://oss.example/.../img-xxx.png?X-Amz-...")
# RIGHT — the durable /v1 proxy file_url (re-signed each request), or the id
set_reference(url=result["artifacts"][0]["file_url"])
data_set("reference_artifact_id", result["artifacts"][0]["artifact_id"])
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

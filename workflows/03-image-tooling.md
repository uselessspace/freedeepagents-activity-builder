# Workflow 03: Wire image tools (image_generate / image_edit)

Engaged when manifest declares `capabilities: ["image_generate"]` or `["image_generate", "image_edit"]`. Skip if image axis is `none`.

> **State 写法**：本工作流把 `reference_artifact_id` / `reference_url` 等业务字段写到 typed-KV `/instance/data.json`——首选活动 @tool（如 `set_reference(url, artifact_id)`），兜底 `data_set("reference_artifact_id", "art_xxx")`。runtime-derived 字段（`phase`、`last_artifact_url`）自动派生，不需要手动写。

## Decision tree (which tool, which source)

```
1. Does state have reference_artifact_id?
   YES → image_edit(source_artifact_id=state.reference_artifact_id, prompt="...")
         (Never re-generate — style will drift.)
   NO  → continue ↓

2. Does this turn's input include a file_id?
   YES → image_edit(source_file_id="<file_id>", prompt="...")
   NO  → continue ↓

3. Did the user provide an http(s) URL?
   YES → image_edit(source_url="<url>", prompt="...")
   NO  → image_generate(prompt="...")
         (generate+edit-locked image axis: IMMEDIATELY persist artifact.artifact_id + url to state.)
```

## Locked-reference pattern（锁定参考图机制）

For activities with `image_axis = generate+edit-locked`:

```
phase=welcome    →  no image work
   ↓
phase=imagining  →  image_generate(prompt=<refined>) → success → 依次调：
                    set_reference(url=<artifact.url>, artifact_id=<artifact.artifact_id>)
                    # 活动 @tool 内部把 reference_url / reference_artifact_id 同时 data_set 进去
                    emit `<id>.preview` 卡（其 meta.phase = "imagining"，runtime 自动派生 phase）
   ↓
phase=editing    →  emit `<id>.confirmed` 卡（其 meta.phase = "editing"，runtime 派生 phase）
                    后续：image_edit(source_url=<reference_url from typed-KV>, prompt=<delta>)
                    （每轮都用 edit；绝不 re-generate；source_url 永远是 pinned reference）
```

> **`reference_url` 是业务字段（住 typed-KV，由活动 @tool pin）**：image_edit 每轮产新 artifact，runtime 派生的 `last_artifact_url` 会被覆盖为最新 sprite——但 source 必须保持 pinned reference 不变。这是 runtime 推不出的业务语义，必须 LLM 通过活动 @tool（`set_reference`）显式 pin。

> **runtime 派生的 `phase` 不是 escape hatch（不要手写那一份）**：`instance.data` 里的 `phase` 由卡的 `meta.phase` 派生。emit `<id>.preview` 自动让 phase = "imagining"，emit `<id>.confirmed` 自动让 phase = "editing"。这条红线**只针对 runtime 派生的那份**——在 `data.schema.json` 声明你自己的业务 `phase` 并用活动 @tool 直写推进（配相位守卫）是合法且官方推荐的另一命名空间，两者互不干扰；见 [../policies/output-protocol.md](../policies/output-protocol.md)「两个 phase 命名空间」。

如用户明确要求重置参考图：调 `set_reference(url="", artifact_id="")`（或对应的 reset @tool），再 emit 一张 `<id>.preview` 卡（meta.phase="imagining" 派生 phase 回退）。

## Store mode, quota, and tool-return shape

These are authority content, not repeated here:

- **`store=` (auto / oss / sandbox)** + the durable `/v1` proxy + locked-reference REQUIRES `oss`: [../references/store-mode-table.md](../references/store-mode-table.md).
- **Per-turn quota**: `IMAGE_GEN_MAX_PER_TURN` (default 4) is **shared** by generate + edit; plan ≤2/turn. Details in [../references/image-tools.md](../references/image-tools.md).
- **Tool-return shape** (`result["artifacts"][0]` — `file_url` / `sandbox_path` / `storage_key` …): [../references/image-tools.md](../references/image-tools.md) §产物如何展示. The LLM just plugs `file_url` into card image variables; the runtime auto-registers the persisted artifact.

## Failure handling (integration-time triage)

Tool returns `{"error": "..."}`; **never auto-retry the same prompt+source** (the provider already decided — content-filter / source-not-found / size, not a transient blip). Emit an error card, do **NOT** modify state on failure.

| Error fragment | Likely cause | Fix |
|---|---|---|
| `content` / `safety` / `policy` | content filter | rewrite prompt |
| `source` / `not found` / `404` | source url/artifact gone | re-fetch reference or ask user to re-upload |
| `size` / `dimension` | unsupported size | change `size=` arg |
| `quota` / `rate` | budget exhausted | wait for next turn |

## Hand-off

```
Image tooling integrated for <id>.
Proceeding to <04-derive-frontend.md | 06-verify-and-ship.md>.
```

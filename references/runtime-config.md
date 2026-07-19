# runtime.json — per-activity runtime config

`activities/<id>/runtime.json` holds per-activity runtime knobs. It is
**whitelist-only**: any key outside the table below is a verifier error.

- **Schema**: [`schemas/runtime.schema.json`](../schemas/runtime.schema.json)
- **Whitelist authority**: `ALLOWED_RUNTIME_FIELDS` in
  [`tools/activity_verifier.py`](../tools/activity_verifier.py) (canonical;
  the repo-root `tools/activity_verifier.py` re-exports it).
- **Source of truth for fields/defaults**: `app/models.py`
  `ActivityRuntimeConfig`. Keep this doc, the schema, and the verifier in sync
  with it.

All fields are optional; omit `runtime.json` entirely if you need no overrides.

| Field | Type | Default | Use it when |
|---|---|---|---|
| `llm_timeout_seconds` | int 1–600 | 60 | Per-turn LLM timeout; bump to ~180 for image-heavy turns. |
| `llm_max_output_tokens` | int ≥1 | env `ACTIVITY_LLM_MAX_OUTPUT_TOKENS` | Long-narrative activities (long-form story output). |
| `docker_timeout_seconds` | int 1–1800 | 120 | Activities that genuinely run long sandbox commands. |
| `max_distinct_support_reads` | int ≥0 | 3 (`0` = unlimited) | Cap distinct workflow/policy/reference reads per turn. `skill_sources` files are exempt. |
| `skill_egress_similarity_threshold` | number 0.0–1.0 | 0.60 | Reject output windows whose character n-gram containment against one protected non-card Skill reaches this threshold. Dedicated `cards` / `*-cards` skills are excluded. |
| `data_schema_enabled` | bool | `false` | Opt into the typed-KV data store. Requires `data.schema.json`. See [data-store-tools.md](data-store-tools.md). |
| `write_todos` | bool | `false` | Opt into the deepagents `write_todos` planner — only for genuinely multi-step (3+) pipeline turns. See [subagents.md](subagents.md). |
| `auto_memory_enabled` | bool \| null | `null` (follow global `AUTO_MEMORY_ENABLED`) | Set `false` to disable the one-line `[auto]` gist for activities whose canonical card sequences look duplicated when echoed. See `app/auto_memory.py`. |
| `sse_debug_view` | object | secure-off | Bridge trace tool/llm events onto the chat SSE stream. **Required** (declare it explicitly, even as `{}`) when `data.schema.json` has any `x-auto-inject:false` field. Fields below. |
| `image_generate_model` | string | env `IMAGE_GEN_MODEL` | Per-activity override of `image_generate`'s model id. Accepts a Wanxiang model (e.g. `wan2.7-image-pro`) **or** a Doubao/Seedream model (e.g. `doubao-seedream-5-0-260128`); the platform routes to the right backend by model name. You pick the model — nothing else. |
| `image_edit_model` | string | env `IMAGE_EDIT_MODEL` | Per-activity override of `image_edit`'s model id. Same Wanxiang-or-Doubao routing by model name. |

### `sse_debug_view` sub-fields

| Field | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | `false` | Master switch (secure by default). |
| `include_tool_input` | bool | `true` | Include tool args in `tool_invoked`. |
| `include_tool_output` | bool | `true` | Include tool returns in `tool_completed`. |
| `include_llm_messages` | bool | `false` | Reserved — prompts/messages stay out of SSE even when enabled; read `trace.jsonl` for full prompts. |
| `redact_tools` | string[] | `[]` | Tools whose start/end still fire (timing visible) but input/output become `"<redacted>"`. |
| `payload_max_bytes` | int ≥0 | `8192` | Per-event input/output JSON byte cap; oversized values truncated with `truncated:true`. |

## Examples

```jsonc
// Minimal: longer LLM timeout for an image activity
{ "llm_timeout_seconds": 180 }
```

```jsonc
// Typed-KV data store + hidden-field SSE decision
{
  "data_schema_enabled": true,
  "sse_debug_view": { "enabled": true, "redact_tools": ["data_get"] }
}
```

```jsonc
// Turn off the auto-memory gist for a canonical-card activity
{ "auto_memory_enabled": false }
```

```jsonc
// Use Doubao/Seedream for this activity's image generation + editing
{
  "image_generate_model": "doubao-seedream-5-0-260128",
  "image_edit_model": "doubao-seedream-5-0-260128"
}
```

# manifest.json field reference

Schema: `<package>/schemas/manifest.schema.json`. This doc explains each field with examples.

## Contents

- Required: `activity_type_id` · `name` · `description` · `model` · `skill_sources` · `entrypoint` · `input_modes`
- Optional: `capabilities` · `tools_module` · `dsl_builder_module` · `handlers_module` · `graph_model` · `sandbox_env` · catalog fields
- NOT allowed（白名单外字段）

## activity_type_id (required)

```json
"activity_type_id": "weather-buddy"
```

- Pattern: `^[a-z][a-z0-9-]{1,30}$`
- Must equal the `activities/<id>/` directory name
- Used in URLs (`/preview/<activity_type_id>/...`), Static Preview routing, and the in-process activity registry
- **不要在部署后改这个*值*（slug）** — 路由和实例目录都按它寻址（例如 `runtime/instances/<activity_type_id>/<instance_id>/…`），改值会断开已有实例。
- manifest 只允许这一项类型标识；`activity_id` 在 Preview URL 与资源引用中表示实例，不是 manifest 字段。

## name (required)

```json
"name": "天气搭子"
```

User-facing display name. Chinese is fine. Used in activity picker UIs.

## description (required)

```json
"description": "把今日天气编成一句俏皮话。"
```

One-line discovery hint. Don't describe implementation; describe what the user gets.

## model (required)

```json
"model": "deepseek:deepseek-v4-flash"
```

`<provider>:<model-id>` format. Common values:

| Model | Suitable for |
|---|---|
| `deepseek:deepseek-v4-flash` | Cards-only, simple decisions, cost-sensitive (the common default) |
| `deepseek:deepseek-v4-pro` | Stronger reasoning / heavier tool use, still text |
| `dashscope:qwen-plus` | Image understanding / structured-output graph extraction (also used as `graph_model`) |

## skill_sources (required)

```json
"skill_sources": ["skills"]                                  // load all skills/
"skill_sources": ["skills/weather-host", "skills/weather-cards"]  // load only listed
"skill_sources": ["skills/host", "skills/tavily-search", "skills/weather-zh"]  // multi-source
```

Strings either equal `"skills"` (load entire dir) or `"skills/<subdir>"` (load specific). Each listed dir must contain a `SKILL.md`.

## entrypoint (required)

```json
"entrypoint": "AGENTS.md"
```

Always literal `"AGENTS.md"`. The runtime currently doesn't support other values.

## input_modes (required)

```json
"input_modes": ["text"]                  // text only
"input_modes": ["text", "image"]         // user can attach images
"input_modes": ["text", "file", "image"] // accept all
```

Subset of `{"text", "file", "image"}`. The runtime uses this to size the upload widget; activities that don't accept images shouldn't list `"image"`.

## capabilities (optional)

```json
"capabilities": ["image_generate"]                     // generate-only
"capabilities": ["image_generate", "image_edit"]       // generate + edit
"capabilities": ["image_generate", "tts_generate"]     // images + clone-voice narration
"capabilities": ["asr"]                                  // transcribe this-turn audio uploads
```

Recognized values: `image_generate` / `image_edit` / `tts_generate` / `read_document` / `asr` — the whitelist authority is [../policies/capabilities.md](../policies/capabilities.md) (any other value → verifier ERROR). Per-capability docs: [image-tools.md](image-tools.md) / [tts-tools.md](tts-tools.md) / [document-tools.md](document-tools.md) / [asr-tools.md](asr-tools.md).

## tools_module (optional)

```json
"tools_module": "tools"
```

Relative activity module name without `.py`. The file must exist at `activities/<id>/tools.py` and export `make_tools(ctx)`. Use this for narrow business tools that mutate typed-KV, publish uploaded files, or trigger Static Preview refresh. Tool names must not collide with built-in tools. To split logic into helper files, follow [activity-python-modules.md](activity-python-modules.md).

## dsl_builder_module (optional, Static Preview)

```json
"dsl_builder_module": "dsl_builder"
```

Relative activity module name without `.py`. The file must exist at `activities/<id>/dsl_builder.py` and export `build(instance_dir) -> dict`. Declaring this enables `/preview/<activity_type_id>/<instance_id>/api/dsl.json` and `/api/dsl/stream`; the activity must also have a `site/` directory that builds to `site/dist/index.html`.

## handlers_module (optional)

```json
"handlers_module": "handlers"
```

Relative activity module name without `.py`. Exposes SPA-callable business functions at `POST /preview/<activity_type_id>/<instance_id>/api/<handler_name>`. A handler-only activity does not need `tools.py`; if the Agent also needs the same operation, place its validation/state transition in a shared plain function and expose thin handler + @tool adapters. When `handlers.py` shares code with helper files, load them per [activity-python-modules.md](activity-python-modules.md) so prompt/logic edits hot-reload via dev_sync.

## graph_model (optional)

```json
"graph_model": "dashscope:qwen-plus"
```

Optional second `<provider>:<model_id>` override used by activities that run a heavier model on a side track (e.g. structured-output extraction on a stronger model while chat stays on the default). Same pattern as `model`. Leave unset if you don't have a second track.

## sandbox_env (optional)

```json
"sandbox_env": ["TMDB_API_KEY"]
```

Declares activity-scoped secret **NAMES**. The runtime exposes **only these names** through `ctx.get_secret(name)` for in-process tools/handlers and injects them into **this activity's** Docker sandbox.

- **Names only — never values.** Put values in administrator-managed `secrets/<activity_type_id>.env`; `/dev/sync` never packages that directory. The current private-repository deployment may Git/CI-sync those files, while `.dockerignore` keeps them out of image build contexts. See `secrets/README.md`.
- **Least privilege.** Each name resolves *only* from this activity's own `secrets/<activity_type_id>.env` (and `secrets/_shared.env`), **never from arbitrary host env** — so declaring `DEEPSEEK_API_KEY` (or any platform secret) gets you nothing unless an admin explicitly placed that value in your activity's secret file.
- Names must match `^[A-Z][A-Z0-9_]*$`.
- Names beginning with `FDA_ADMIN_` are platform policy and cannot be declared or injected.
- This is the per-activity successor to the global `ACTIVITY_SANDBOX_ENV_ALLOWLIST` (which still works but is shared by every activity). Prefer declaring per activity so the requirement travels with the activity and hot-syncs.

Setup is two steps: (1) declare the name here; (2) let an administrator set the value in `secrets/<activity_type_id>.env`. A missing value is simply unavailable.

## catalog fields (optional): enabled / sort_order

```json
"enabled": true,
"sort_order": 0
```

Metadata for the platform's activity-type catalog (Go's `GET /v1/activity-types` sync). `enabled` (default `true`) hides an activity type from product listing without deleting it; `sort_order` (default `0`, lower sorts first) gives a stable display order. Both are optional with safe defaults — existing manifests are unaffected.

## NOT allowed

Anything else. The verifier checks against an exact whitelist. Examples of fields people sometimes try to add (and where they actually belong):

| Field someone tried | Belongs in |
|---|---|
| `default_city`, `theme_color` | activity `data.schema.json` typed-KV fields or host skill references |
| `frontend_mode` | infer from `dsl_builder_module` |
| `tool_specs` | `tools.py` docstrings and LangChain tool schemas |
| `version` | `runtime.json` (no, actually still not — bump implicit at git tag) |
| `tags`, `category` | (out of scope V1 — propose to runtime team) |

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
- **不要在部署后改这个*值*（slug）** — 路由和实例目录都按它的值寻址（`activities/<activity_type_id>/<activity_id>/…`），改值会断掉一切。

### legacy `activity_id` → `activity_type_id` 改名安全窗口（verifier W8）

旧 manifest 可能仍用 `activity_id` 承载这个值；新 manifest 必须用 `activity_type_id`。verifier 对前者发 [W8](verifier-checks.md) 警告。关于"改名会不会装不上"：

- **把*键名*从 legacy `activity_id` 改成 `activity_type_id`（值不变）是安全的前向迁移**：runtime 的 `ActivityManifest` 以 `activity_type_id` 为 canonical 字段，`activity_id` 是加载前就被归一化掉的 legacy 别名（`normalize_legacy_activity_id`，`mode="before"`）。所以改名是"往规范名靠"，不是引入新字段。
- **双轨现状**：两者并存且*不等* → 加载报错 / verifier ERROR（[#18](verifier-checks.md)）；只留 legacy `activity_id` → runtime 仍按别名接受、verifier 仅 W8 警告；只留 `activity_type_id` → 正路。**当前 runtime 对 `activity_id` 无 sunset 计划、不会自动升级成 ERROR**——它是永久兼容别名。
- **改键名不需要平台侧配合**：实例数据按 `activity_type_id` 的*值*关联（存储路径就是该值），不按 manifest 里的键名；值不变则关联不变，无需重建实例。
- **唯一前提**：你部署的 runtime 版本已把 `activity_type_id` 作为 canonical（当前 runtime 即是）。本仓库的平台 runtime 未打版本 tag，若不放心生产版本，**先在目标 runtime 上验证一个改名后的 manifest 能正常加载，再批量改**即可。

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
```

Recognized values: `image_generate` / `image_edit` / `tts_generate` / `read_document` — the whitelist authority is [../policies/capabilities.md](../policies/capabilities.md) (any other value → verifier ERROR). Per-capability docs: [image-tools.md](image-tools.md) / [tts-tools.md](tts-tools.md) / [document-tools.md](document-tools.md).

## tools_module (optional)

```json
"tools_module": "tools"
```

Relative activity module name without `.py`. The file must exist at `activities/<id>/tools.py` and export `make_tools(ctx)`. Use this for narrow business tools that mutate typed-KV, publish uploaded files, or trigger Static Preview refresh. Tool names must not collide with built-in tools. To split logic into helper files, follow [activity-python-modules.md](activity-python-modules.md).

## dsl_builder_module (optional, Static Preview)

```json
"dsl_builder_module": "dsl_builder"
```

Relative activity module name without `.py`. The file must exist at `activities/<id>/dsl_builder.py` and export `build(instance_dir) -> dict`. Declaring this enables `/preview/<activity_type_id>/<activity_id>/api/dsl.json` and `/api/dsl/stream`; the activity must also have a `site/` directory that builds to `site/dist/index.html`.

## handlers_module (optional)

```json
"handlers_module": "handlers"
```

Relative activity module name without `.py`. Exposes pure business functions; activity @tools wrap them and the SPA reaches them via `POST /preview/<activity_type_id>/<activity_id>/api/<handler_name>` — so SPA-side actions and the @tool versions share one implementation. When `handlers.py` shares code with helper files, load them per [activity-python-modules.md](activity-python-modules.md) so prompt/logic edits hot-reload via dev_sync.

## graph_model (optional)

```json
"graph_model": "dashscope:qwen-plus"
```

Optional second `<provider>:<model_id>` override used by activities that run a heavier model on a side track (e.g. structured-output extraction on a stronger model while chat stays on the default). Same pattern as `model`. Leave unset if you don't have a second track.

## sandbox_env (optional)

```json
"sandbox_env": ["TMDB_API_KEY"]
```

Declares the environment variable **NAMES** this activity's sandbox needs — e.g. an external API key a Skill's `curl` reads (`curl "...?api_key=$TMDB_API_KEY"`). The runtime injects **only these names** into **this activity's** sandbox.

- **Names only — never values.** The activity folder is synced via `/dev/sync`, git-tracked, and shared; a real key here would leak (and `/dev/sync` atomically replaces the activity dir, so a secret file inside it gets wiped anyway). Put the **value** server-side in `secrets/<activity_type_id>.env` (gitignored, never packed). See the repo's `secrets/README.md`.
- **Least privilege.** Each name resolves *only* from this activity's own `secrets/<activity_type_id>.env` (and `secrets/_shared.env`), **never from arbitrary host env** — so declaring `DEEPSEEK_API_KEY` (or any platform secret) gets you nothing unless an admin explicitly placed that value in your activity's secret file.
- Names must match `^[A-Z][A-Z0-9_]*$`.
- This is the per-activity successor to the global `ACTIVITY_SANDBOX_ENV_ALLOWLIST` (which still works but is shared by every activity). Prefer declaring per activity so the requirement travels with the activity and hot-syncs.

Setup is two steps: (1) declare the name here; (2) on the server, drop the value into `secrets/<activity_type_id>.env`. A name with no value on the server is simply not injected.

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

# Workflow 02: Author the backend (6 artifacts)

All runtime modes pass through here. Stop before any frontend / image / verification work.

> Run scaffold + later verifier from **`<project-root>`** (your repo holding
> `activities/`). The scaffold creates `activities/<id>/` under the git root, or
> the current directory if not in a git repo — so don't run it from inside
> `<package>`.

Activities run in **card-system mode** with **typed-KV business data** (`runtime.json.data_schema_enabled: true`). The scaffolded template, host SKILL.md, and policies all reference the card-system tool surface (`card_emit_template`, `artifact_emit`, `memory_add`, plus retract variants). Business state lives in typed-KV `/instance/data.json` (declared via `data.schema.json`) and is mutated through activity @tools or the generic `data_*` tools. Runtime-derived state (`phase` / counts / `last_*_id`) is computed at turn end from emitted cards and injected via `current_instance_state`. When done, just stop; the runtime assembles the final output from your tool calls. 工具的权威签名与调用范例见 [../references/card-system-tools.md](../references/card-system-tools.md)；活动 @tool 参数 schema（DeepSeek strict 模式）与其他输出纪律见 [../policies/llm-output-discipline.md](../policies/llm-output-discipline.md)。

## Step 1: Scaffold from template

```bash
bash <package>/tools/scaffold-backend.sh <activity-id> "<display-name>"
```

Where `<package>` resolves to wherever this skill is installed (typically `packages/freedeepagents-activity-builder/`). The script:
1. Validates the id (`^[a-z][a-z0-9-]{1,30}$`)
2. `cp -r <package>/templates/activity-template/ activities/<id>/`
3. Substitutes `template-activity` → `<id>` and `模板活动` → `<display-name>` in file contents
4. Renames files/dirs containing `template-activity`
5. Prints next-step checklist

## Step 2: Fill the 6 artifacts in order

| # | Artifact | Path | Reference |
|---|---|---|---|
| 1 | manifest | `activities/<id>/manifest.json` | [../references/manifest-fields.md](../references/manifest-fields.md) + `<package>/schemas/manifest.schema.json` |
| 2 | runtime config | `activities/<id>/runtime.json` | [../references/runtime-config.md](../references/runtime-config.md) + `<package>/schemas/runtime.schema.json` (set `data_schema_enabled: true`) |
| 3 | data schema | `activities/<id>/data.schema.json` | [../references/data-store-tools.md](../references/data-store-tools.md) — declares the activity's typed-KV business shape with `default`, `properties`, optional per-key `x-auto-inject` |
| 4 | activity entrypoint | `activities/<id>/AGENTS.md` (≤80 lines) | [../policies/agents-md-thin.md](../policies/agents-md-thin.md) |
| 5 | host skill | `activities/<id>/skills/<id>-host/SKILL.md` (≤120 lines) | [../references/host-skill-template.md](../references/host-skill-template.md) |
| 6 | card templates | `activities/<id>/card_templates/*.json` (+ matching `*.vars.json` per template) | [../references/card-block-types.md](../references/card-block-types.md) — **the 6 block types** (`markdown` / `info` / `form` / `action` / `image` / `audio`) with schema, FormField rules, form-vs-action decision tree. Vars schema: `<package>/schemas/card-vars.schema.json`. Activities needing an intake form (collecting user input by fields) use a `form` block here; activities that only need a few clickable options use `action` instead. |

Optional 7th: `activities/<id>/skills/<id>-cards/` — split out only if host SKILL.md exceeds 120 lines because of card-related content.

> The scaffold also drops `output.schema.json` (a `$ref` to the shared
> transport schema) and a `<id>-cards/` skill stub. `output.schema.json` is
> auto-generated, not verified, and not authored by you — **leave it as-is**.

## Step 3 (Static Preview only): declare activity tools + DSL builder

For a Static Preview activity, add these fields to `manifest.json`:

```jsonc
"tools_module": "tools",
"dsl_builder_module": "dsl_builder"
```

Then create:

- `activities/<id>/tools.py` exporting `make_tools(ctx)` — wraps the typed-KV writes into user-semantic activity tools (e.g. `add_note(content, tags)` instead of forcing the LLM to compose `data_append("notes", {...})`). Multi-store fan-out (gbrain mirror, search index, etc.) goes inside these tools as best-effort side-effects — see [../policies/multi-store-tool-design.md](../policies/multi-store-tool-design.md). Need a side-channel LLM call inside a tool/handler (one-shot text, JSON, or vision/看图)? Use `ctx.llm` — never a hand-rolled HTTP client or provider key (the verifier hard-blocks that); see [../references/ctx-llm.md](../references/ctx-llm.md).
- `activities/<id>/dsl_builder.py` exporting `build(instance_dir) -> dict` — pure function reading `data.json` and returning the DSL shape your SPA consumes.
- `activities/<id>/site/` in [04-derive-frontend.md](04-derive-frontend.md).

Splitting any of these into helper `.py` files? Load siblings with the
canonical loader in [../references/activity-python-modules.md](../references/activity-python-modules.md)
so prompt/logic edits hot-reload via dev_sync on the next turn.

## Step 4 (any mode): declare third-party Python deps

If your `tools.py` / `dsl_builder.py` / `handlers.py` (or helper modules they
ship) import any third-party Python package, declare it in
`activities/<id>/requirements.txt` (the scaffold ships an all-comment starter).
The runtime shares one venv across all activities, so an undeclared import
`ImportError`s on a fresh host — and the verifier blocks it. Pin with `==`;
don't declare stdlib, platform-baseline packages, or `app.*`. Prefer the stdlib
or a runtime capability before adding a dependency. Full rules:
[../references/python-dependencies.md](../references/python-dependencies.md).

## Red-line self-check (before hand-off)

- [ ] No activity-specific code in `app/` / `frontend-src/` / `schemas/` ([policy](../policies/runtime-boundary.md))
- [ ] manifest.json validates against `<package>/schemas/manifest.schema.json`
- [ ] runtime.json validates against `<package>/schemas/runtime.schema.json` with `data_schema_enabled: true` set
- [ ] Every activity @tool in `tools.py` passes the DeepSeek strict-mode schema self-check (no bare `list`/`dict` params; parameterized containers like `list[str]` / `list[dict]` are legal, JSON-encoded `str` remains the most cross-model-compatible fallback for complex/optional-field payloads — see [../policies/llm-output-discipline.md](../policies/llm-output-discipline.md) §8d; run `skills/activity-verify/scripts/strict-tool-schema-check.py` to confirm)
- [ ] data.schema.json exists with `type: object`, a top-level `default` block, `properties` covering every business field, and `x-auto-inject` set per key (true for fields the LLM should see in the prompt; false for secrets / large sets)
- [ ] Every third-party Python package imported by `tools.py` / `dsl_builder.py` / `handlers.py` (or their helpers) is declared, pinned with `==`, in `activities/<id>/requirements.txt`; stdlib / platform-baseline / `app.*` are NOT declared ([reference](../references/python-dependencies.md))
- [ ] If Static Preview: manifest has `dsl_builder_module` + `tools_module`; both `tools.py` (exports `make_tools(ctx)`) and `dsl_builder.py` (exports `build(instance_dir)`) exist; `site/` exists
- [ ] Activity @tools (in `tools.py`) wrap typed-KV writes with user-semantic names; tool names do not collide with built-ins
- [ ] AGENTS.md ≤80 lines; routes to `skills/<id>-host/SKILL.md`
- [ ] host SKILL.md ≤120 lines; supporting files under `workflows/`/`policies/`/`references/`

## Hand-off

```
Backend authored for <id>. Runtime mode <Card-only|Static Preview>.
Image axis: <none|generate-only|generate+edit-locked>.
Proceeding to <next-step>.
```

Where `<next-step>` is:
- Card-only & image_axis=none → [06-verify-and-ship.md](06-verify-and-ship.md)
- image_axis ≠ none → [03-image-tooling.md](03-image-tooling.md)
- Static Preview → [04-derive-frontend.md](04-derive-frontend.md)

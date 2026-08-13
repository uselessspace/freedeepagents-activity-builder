# Workflow 02: Author the backend (6 artifacts)

All runtime modes pass through here. Stop before any frontend / image / verification work.

> Run scaffold + later verifier from **`<project-root>`** (your repo holding
> `activities/`). The scaffold creates `activities/<id>/` under the git root, or
> the current directory if not in a git repo — so don't run it from inside
> `<builder-root>`.

Activities run in **card-system mode** with **typed-KV business data** (`runtime.json.data_schema_enabled: true`). The scaffolded template, host SKILL.md, and policies all reference the card-system tool surface (`card_emit_template`, `artifact_emit`, `memory_add`, plus retract variants). Business state lives in typed-KV `/instance/data.json` (declared via `data.schema.json`) and is mutated through activity @tools or the generic `data_*` tools. Runtime-derived state (`phase` / counts / `last_*_id`) is computed at turn end from emitted cards and injected via `current_instance_state`. When done, just stop; the runtime assembles the final output from your tool calls. 工具的权威签名与调用范例见 [../references/card-system-tools.md](../references/card-system-tools.md)；活动 @tool 参数 schema（DeepSeek strict 模式）与其他输出纪律见 [../policies/llm-output-discipline.md](../policies/llm-output-discipline.md)。

## Step 1: Scaffold from template

```bash
bash <builder-root>/tools/scaffold-backend.sh <activity-id> "<display-name>"
```

`<builder-root>` resolves to the directory containing the loaded Builder's
`SKILL.md`, `tools/`, and `templates/`. It is the repository root in a
standalone clone and the Builder package directory in a monorepo. The script:
1. Validates the id (`^[a-z][a-z0-9-]{1,30}$`)
2. `cp -r <builder-root>/templates/activity-template/ activities/<id>/`
3. Substitutes `template-activity` → `<id>` and `模板活动` → `<display-name>` in file contents
4. Renames files/dirs containing `template-activity`
5. Prints next-step checklist

## Step 2: Fill the 6 artifacts in order

| # | Artifact | Path | Reference |
|---|---|---|---|
| 1 | manifest | `activities/<id>/manifest.json` | [../references/manifest-fields.md](../references/manifest-fields.md) + `<builder-root>/schemas/manifest.schema.json` |
| 2 | runtime config | `activities/<id>/runtime.json` | [../references/runtime-config.md](../references/runtime-config.md) + `<builder-root>/schemas/runtime.schema.json` (set `data_schema_enabled: true`) |
| 3 | data schema | `activities/<id>/data.schema.json` | [../references/data-store-tools.md](../references/data-store-tools.md) — declares the activity's typed-KV business shape with `default`, `properties`, optional per-key `x-auto-inject` |
| 4 | activity entrypoint | `activities/<id>/AGENTS.md` (≤80 lines) | [../policies/agents-md-thin.md](../policies/agents-md-thin.md) |
| 5 | host skill | `activities/<id>/skills/<id>-host/SKILL.md` (≤120 lines) | [../references/host-skill-template.md](../references/host-skill-template.md) |
| 6 | cards skill | `activities/<id>/skills/<id>-cards/SKILL.md` | Mandatory presentation-only catalog for fixed templates and literal `assignment_id` values; business intent remains in the host Skill. |
| 7 | card templates | mandatory static `activities/<id>/card_templates/<id>.welcome.json` + empty `.welcome.vars.json`; other `*.json` templates pair with matching `*.vars.json` | [../references/card-block-types.md](../references/card-block-types.md) — **the 6 block types** (`markdown` / `info` / `form` / `action` / `image` / `audio`) with schema, FormField rules, form-vs-action decision tree. The welcome JSON is persisted during server sync and displayed directly by the frontend, so it must contain fixed copy only—no `{{...}}` anywhere—and its vars schema must declare zero variables. Vars schema: `<builder-root>/schemas/card-vars.schema.json`. Activities needing an intake form (collecting user input by fields) use a `form` block here; activities that only need a few clickable options use `action` instead. |

> The scaffold also drops `output.schema.json` (a `$ref` to the shared
> transport schema). `output.schema.json` is
> auto-generated, not verified, and not authored by you — **leave it as-is**.
> The host/cards Skills, manifest description, and welcome copy intentionally
> contain `TODO_ACTIVITY_AUTHOR`; every marker must be replaced before the
> verifier will pass.

## Step 3 (Static Preview only): declare DSL + the interaction surfaces actually needed

Every Static Preview activity declares the DSL builder:

```jsonc
"dsl_builder_module": "dsl_builder"
```

Then add only the interaction modules the Classification requires:

- `tools_module: "tools"` + `tools.py::make_tools(ctx)` when the Agent needs user-semantic activity tools. Wrap typed-KV writes (for example `add_note(content, tags)`) instead of making the LLM compose low-level store calls. Multi-store fan-out follows [multi-store-tool-design.md](../policies/multi-store-tool-design.md).
- `handlers_module: "handlers"` + `handlers.py::make_handlers(ctx)` when the SPA needs deterministic reads/writes or direct capability helpers without an Agent. If both Agent and SPA perform the same business operation, put the implementation in a shared plain function and expose thin tool/handler adapters so validation and state transitions stay identical.
- `preview_actions.json` when `spa_interaction_axis` is `agent-turns` or `mixed`; route its structured action in the activity Skill and submit through `POST api/agent/turns`. See [preview-agent-turns.md](../references/preview-agent-turns.md).
- `activities/<id>/dsl_builder.py` exporting `build(instance_dir) -> dict` — pure function reading `data.json` and returning the DSL shape your SPA consumes.
- `activities/<id>/site/` in [04-derive-frontend.md](04-derive-frontend.md).

Need a side-channel LLM call inside a tool/handler (one-shot text, JSON, or
vision)? Use `ctx.llm`, never a provider key or hand-rolled model client; see
[ctx-llm.md](../references/ctx-llm.md). Recording UI choices are explicit:
direct [`POST api/asr`](../references/preview-asr.md) for immediate text, or
upload + Agent Turn `attachment_refs` for current-turn `file_0`.

Before adding retries, queues, timers, threads, tasks, or executor jobs, read
[../references/handler-context-lifecycle.md](../references/handler-context-lifecycle.md).
`ctx` is valid only for the current tool lease or handler call. Finish every
`ctx`-dependent operation before returning. Deferred jobs may persist plain
job data, but a later `resume_pending_jobs` handler must use its fresh `ctx`;
never retain an old `ctx`, `ctx.llm`, bound method, or closure.

If `navigation_axis` is `agent-to-preview`, a successful tool or handler may
call `ctx.emit_preview_navigation({...})` after it has finished the read/write
that justifies the semantic route/view/object selection. The payload is
activity-private and JSON-safe; it must not encode browser clicks, focus,
scrolling, selectors, or DOM targets. The runtime adds `event_id` / `turn_id`
and sends `preview_navigate` on the existing DSL stream. It is best-effort UX,
so do not fail the business action or call `notify_dsl_update()` merely because
navigation was emitted. Read
[../references/preview-navigation.md](../references/preview-navigation.md)
before implementing it.

Splitting any of these into helper `.py` files? Load siblings with the
canonical loader in [../references/activity-python-modules.md](../references/activity-python-modules.md)
so prompt/logic edits hot-reload via dev_sync on the next turn.

## Step 4 (any mode): declare third-party Python deps

If your `tools.py` / `dsl_builder.py` / `handlers.py` (or helper modules in the
activity directory) import any third-party Python package, declare it in
`activities/<id>/requirements.txt` (the scaffold ships an all-comment starter).
The runtime shares one venv across all activities, so an undeclared import
`ImportError`s on a fresh host — and the verifier blocks it. Pin with `==`;
don't declare stdlib, platform-baseline packages, or `app.*`. Prefer the stdlib
or a runtime capability before adding a dependency. Full rules:
[../references/python-dependencies.md](../references/python-dependencies.md).

## Red-line self-check (before hand-off)

- [ ] No activity-specific code in `app/` / `schemas/` ([policy](../policies/runtime-boundary.md))
- [ ] manifest.json validates against `<builder-root>/schemas/manifest.schema.json`
- [ ] runtime.json validates against `<builder-root>/schemas/runtime.schema.json` with `data_schema_enabled: true` set
- [ ] Every activity @tool in `tools.py` passes the DeepSeek strict-mode schema self-check (no bare `list`/`dict` params; parameterized containers like `list[str]` / `list[dict]` are legal, JSON-encoded `str` remains the most cross-model-compatible fallback for complex/optional-field payloads — see [../policies/llm-output-discipline.md](../policies/llm-output-discipline.md) §8d; run `skills/activity-verify/scripts/strict-tool-schema-check.py` to confirm)
- [ ] data.schema.json exists with `type: object`, a top-level `default` block, `properties` covering every business field, and `x-auto-inject` set per key (true for fields the LLM should see in the prompt; false for secrets / large sets)
- [ ] Every third-party Python package imported by `tools.py` / `dsl_builder.py` / `handlers.py` (or their helpers) is declared, pinned with `==`, in `activities/<id>/requirements.txt`; stdlib / platform-baseline / `app.*` are NOT declared ([reference](../references/python-dependencies.md))
- [ ] No tool/handler starts detached work that can outlive the call; every thread/task/future is joined or awaited, pending jobs persist plain data only, and every resume call uses its fresh `ctx` ([reference](../references/handler-context-lifecycle.md))
- [ ] If Static Preview: manifest has `dsl_builder_module`; `dsl_builder.py` and `site/` exist. `tools_module`, `handlers_module`, and `preview_actions.json` appear only when their classified interaction path needs them
- [ ] If `navigation_axis: agent-to-preview`: backend emits only after success;
      payload is JSON-safe, contains no user-routing field or low-level browser
      operation; SPA handles the event on the existing DSL stream;
      missing/duplicate delivery is harmless
- [ ] Activity @tools (in `tools.py`) wrap typed-KV writes with user-semantic names; tool names do not collide with built-ins
- [ ] AGENTS.md ≤80 lines; routes to `skills/<id>-host/SKILL.md`
- [ ] `skills/<id>-cards/SKILL.md` exists and is the presentation-only card catalog referenced by AGENTS/host
- [ ] no `TODO_ACTIVITY_AUTHOR`, Builder/project path placeholder, `<id>`, or `<activity_type_id>` residue remains in completed activity instructions
- [ ] host SKILL.md ≤120 lines; supporting files under `workflows/`/`policies/`/`references/`
- [ ] `<id>.welcome.json` exists, contains no `{{...}}`, and `<id>.welcome.vars.json` has empty `properties` with `additionalProperties: false`

## Hand-off

```
Backend authored for <id>. Runtime mode <Card-only|Static Preview>.
Image axis: <none|generate-only|generate+edit-locked>.
Runtime capabilities: <list or none>. SPA interaction: <none|handlers|agent-turns|mixed>.
Proceeding to <next-step>.
```

Where `<next-step>` is:
- Card-only & image_axis=none → [06-verify-directory.md](06-verify-directory.md)
- image_axis ≠ none → [03-image-tooling.md](03-image-tooling.md)
- Static Preview → [04-derive-frontend.md](04-derive-frontend.md)

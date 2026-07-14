# Verifier checks reference

Source of truth: `<package>/tools/activity_verifier.py`. This doc summarizes what gets checked.

## Invocation

```bash
python <package>/tools/activity_verifier.py [<root>]
```

`<root>` defaults to the current directory; it must be the **project root that
contains `activities/`** (not an individual activity dir, not the plugin dir).
The verifier scans every `activities/<id>/manifest.json` directly under it.
Requires **Python ≥ 3.10** (stdlib only, no platform repo; 3.9 exits with a clear
version error — see INSTALL.md "Toolchain requirements").

Output:
```
ERROR <path>: <message>
WARNING <path>: <message>
scanned <N> activities: <E> ERROR, <W> WARNING
```

Exit code: `1` if any errors, `0` if clean — and `2` if **zero** activities were
found (wrong directory: nothing was actually verified, so a silent "pass" can't
masquerade as success). Always confirm the `scanned N` line shows the count you
expect.

## Hard checks (ERROR, block ship)

| # | Check | Common cause | Fix |
|---|---|---|---|
| 1 | Manifest field whitelist | unknown field in manifest.json | delete it; move business data into `data.schema.json` if that's where it belongs |
| 2 | Capabilities whitelist | value other than `image_generate` / `image_edit` / `tts_generate` / `read_document` | remove or correct |
| 3 | Runtime config whitelist | unknown field in runtime.json | delete or move it; see `<package>/schemas/runtime.schema.json` for the allowed set |
| 4 | **typed KV data store wiring** | `runtime.data_schema_enabled: true` requires `data.schema.json` to exist | add `data.schema.json`, or flip the flag back to false (新活动默认开启) |
| 5 | **typed KV top-level default** | `data.schema.json` exists but defaults are only under `properties.*.default` | add a schema-level `default` object |
| 6 | Contract files exist + static welcome contract | orphan card template missing `.vars.json`; exact `<id>.welcome.json` missing; welcome contains `{{...}}`; welcome vars schema is non-empty/open | add the paired vars file; add the exact welcome filename; replace welcome placeholders with fixed copy; keep welcome vars at empty `properties` + `additionalProperties: false` |
| 6a | **Card template schema conformance** | `card_templates/*.json` violates `<package>/schemas/card-template.schema.json` — e.g. ImageItem written as `url`/`alt` (must be `read_url`/`title`/`description`), FormField `input_type: "select"` (only `text`/`textarea`/`number`/`file`/`audio`/`hidden` exist) | fix the template; the error message carries the exact `$.card.blocks[i]…` path. A template that fails here is rejected 1:1 by the runtime's OutputCard validation at emit time |
| 6b | **Vars schema conformance** | `*.vars.json` violates `<package>/schemas/card-vars.schema.json` (wrong top-level shape, unknown var `type`, …) | fix the vars file; `{{var}}` placeholders in the template are validated against it at render time |
| 7 | Static Preview module contracts | `tools_module` / `dsl_builder_module` points at missing file or missing `make_tools` / `build` callable | add the module or remove the manifest field |
| 8 | Static Preview site exists | `dsl_builder_module` set but no `site/` directory | create frontend project and build it |
| 9 | Activity tool name collision | activity tool reuses built-in names like `card_emit`, `data_set`, `execute`, `read_file` | rename the activity tool |
| 10 | Generic-runtime boundary | activity-id literal in `app/`, `frontend-src/`, `schemas/` | move logic to `activities/<id>/skills/` |
| 11 | Frontend private state | `frontend-src/` reads `instance.data.*` or activity-private keys | use OutputArtifact / cards instead |
| 12 | DeepAgents skill loading | `app/runner/__init__.py` must call `create_deep_agent(skills=self._skill_sources(manifest))` so native progressive disclosure stays on | restore that argument |
| 13 | **Credential / provider direct access** (since 0.3.0) | activity `.py` imports `app.settings`, calls `get_settings()` / reaches `._settings`, or its code strings reference a platform provider key name (`DEEPSEEK_API_KEY` / `DASHSCOPE_API_KEY` / `OPENAI_API_KEY`) or provider host (`api.deepseek.com` / `dashscope.aliyuncs.com`) — bypasses LLM-gateway metering + cost-ledger billing | LLM (text/JSON/vision) → `ctx.llm`, see `references/ctx-llm.md`; images/TTS → `image_generate` / `tts_generate` capability tools. Scope: only platform-billed providers — generic third-party HTTP (data APIs, web scraping) is NOT flagged. Static AST check at package-verify time; deployed instances are unaffected |
| 14 | **Undeclared third-party Python dependency** | an activity `.py` imports a package that is neither stdlib, nor in the platform baseline (`references/runtime-python-baseline.txt`), nor first-party (`app.*`), nor a sibling module the activity ships, nor declared in the activity's own `requirements.txt` — would `ImportError` on a fresh host | add the package to `activities/<id>/requirements.txt`; see `references/python-dependencies.md` |
| 15 | **Hidden state requires explicit `sse_debug_view`** | `data.schema.json` marks fields `x-auto-inject: false` (hidden state) but `runtime.json` has no `sse_debug_view` key — the SSE debug-view decision must be intentional, not inherited | add `"sse_debug_view": {"enabled": false}` to keep the secure default, or `{"enabled": true, "redact_tools": ["data_get", ...]}` to opt in with hidden-field accessors masked |
| 16 | **Card field-name lint** (heuristic) | `card_templates/*.json` or `skills/*/examples/*.json` uses look-alike field names the runtime rejects: image block `src`/`alt`/`caption` (→ `images: [{read_url, title, description}]`), artifact `file_url` (→ `url`) / `byte_size` (no such field) / missing or empty `artifact_id`, image artifact `kind: "markdown"` (→ `kind: "file"`) | rename to the canonical field; the message carries the exact hint |
| 17 | **File integrity** | a `manifest.json` / `runtime.json` / `card_templates/*.json` is unreadable or invalid JSON; `data.schema.json` isn't a JSON object; `tools.py` / `dsl_builder.py` has a `SyntaxError` | fix the malformed file (the message names it) |
| 18 | **`activity_type_id` / `activity_id` mismatch** | a manifest carries both keys and they differ | make them equal, or keep only `activity_type_id` |
| 19 | **No relative imports in `tools.py`** | `tools.py` / helpers use `from . import x` — the runtime loads them by file path (no package context), so relative imports `ImportError` | load siblings via the file-path loader (see `references/activity-python-modules.md`) |
| 20 | **DeepAgents skill-loading integrity** (companion to #12) | `app/runner` reintroduces a `_skill_instruction_text` helper or globs/rglobs `SKILL.md` itself — both bypass native progressive disclosure | keep skills flowing through `create_deep_agent(skills=...)` |
| 21 | **Static Preview frontend `file:` dependency boundary** | `site/package.json` has `file:` dependencies that are missing, absolute, or resolve outside `activities/<id>/` (for example `file:../../../packages/...`) | vendor the dependency inside the activity, such as `file:vendor/<package>`, so the activity package installs without the Runtime monorepo |

## Soft warnings (advisory — record in Ship Verification, ship proceeds)

Soft warnings are numbered `W1…` to keep them unambiguous next to the hard
checks above (older docs/CHANGELOG entries called W6/W7 "6"/"6a" — same checks).

| # | Check | Reason |
|---|---|---|
| W1 | SKILL.md > 120 lines without supporting files | progressive disclosure failure |
| W2 | Activity AGENTS.md > 80 lines | should be thin entrypoint |
| W3 | AGENTS.md doesn't link to `skills/.../SKILL.md` | discoverability |
| W4 | Skill description < 24 chars / unclear activation conditions | discoverability |
| W5 | AGENTS.md describes outputs as a final JSON payload (`metadata.card_requests=[...]` / `Return one shared ActivityAgentOutput` in instructive context) | rewrite each sub-route as concrete card-system tool calls (`card_emit_template` / activity-tool calls / ...) |
| W6 | Doc references a tool (call syntax `` `tool_name(` `` in AGENTS.md or `skills/**/*.md`) not exported by `tools.py` `make_tools()` | the doc names a renamed/removed/typo'd tool; the LLM would call it and get an error — fix the doc or restore the tool. Bare backtick mentions without `(` are not checked. See `policies/tool-error-protocol.md` |
| W7 | Doc calls an activity tool with a **kwarg its signature doesn't declare** (e.g. `save_nodebook(world_id=...)` when the param is `world_title`) | the doc teaches a wrong argument name; strict tool-call mode rejects unknown args at runtime. Fix the doc or the tool signature. Single-line calls only; tools taking `**kwargs` are skipped |
| W8 | Manifest uses deprecated `activity_id` (without `activity_type_id`) | rename the key to `activity_type_id` |
| W9 | `references/runtime-python-baseline.txt` missing | the dependency check (#14) is skipped — regenerate the baseline so undeclared imports are caught |

## Authority

When this doc disagrees with the verifier source, **the verifier wins**. File a bug to this doc.

## Tips

- Run with grep to focus: `python <package>/tools/activity_verifier.py 2>&1 | grep activities/<your-id>`
- Capture output for the Ship Verification block: `python <package>/tools/activity_verifier.py 2>&1 | tee /tmp/verify.out`

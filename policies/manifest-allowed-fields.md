# Policy: manifest.json field whitelist

## Allowed fields

`manifest.json` is a **closed whitelist**: any field outside it →
`ERROR manifest.json: has disallowed field: <name>` → blocks ship. For the
per-field list (with types, examples, and which are required), see the field
reference — it's the single authority, kept in sync with the verifier and the
schema by `check_schema_sync.py`:

→ **[../references/manifest-fields.md](../references/manifest-fields.md)**

This policy answers the next question: when a field you want *isn't* on that
list, where does it belong instead?

## Where other "I need a new field" cases belong

| You want to express | Goes in |
|---|---|
| Per-instance setting | `data.schema.json` (it's runtime state, not manifest) |
| Behavior flag | host SKILL.md or one of its `policies/` files |
| Activity-specific tool implementation | `activities/<id>/tools.py` + `manifest.tools_module` |
| Static Preview rendering contract | `activities/<id>/dsl_builder.py` + `manifest.dsl_builder_module` |
| SPA-callable business function | `activities/<id>/handlers.py` + `manifest.handlers_module` (then wrap with an @tool in `tools.py`) |
| Side-track model override (e.g. graph extraction) | `manifest.graph_model` |
| Cross-activity shared config | `app/settings.py` (genuinely needs runtime change; design review required) |
| Activity-private domain constant | a `references/` markdown file inside the host skill |

If a manifest field still feels necessary after that, it's a runtime-protocol change — propose it to whoever owns `app/main.py` + `tools/activity_verifier.py`.

## Validation

Use `<package>/schemas/manifest.schema.json` (`$id: https://freedeepagents.dev/schemas/manifest.schema.json`) in your editor or CI to catch this before the verifier does.

## Authority

Source of truth = `tools/activity_verifier.py`'s `ALLOWED_MANIFEST_FIELDS` set. The schema and this doc mirror it; if they disagree, the verifier wins.

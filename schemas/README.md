# JSON Schemas

Canonical schemas for FreeDeepAgents activity files. Use them in your editor (VS Code: add `"json.schemas"` mapping in settings) or in CI to validate authored files.

**Bundle version: 0.4.1** — this schema bundle ships inside the plugin and tracks `.claude-plugin/plugin.json`. `tools/check_schema_sync.py` (run in the platform repo / CI) proves `card-template.schema.json` matches the runtime's `app.models` field-for-field, so an authored file that passes these schemas also passes the runtime's `OutputCard` validation at emit time.

| File | Validates |
|---|---|
| `manifest.schema.json` | `activities/<id>/manifest.json` (closed field whitelist; includes Static Preview + handlers + graph_model + sandbox_env + catalog metadata) |
| `runtime.schema.json` | `activities/<id>/runtime.json` (operational fields including `sse_debug_view`) |
| `card-template.schema.json` | `activities/<id>/card_templates/*.json` (`OutputCard` wrapper + 6 block types: markdown / info / form / action / image / audio) |
| `card-vars.schema.json` | `activities/<id>/card_templates/*.vars.json` (variable definitions for the template's placeholders) |
| `output-artifact.schema.json` | a single entry in `ActivityAgentOutput.artifacts[]` (image_generate / image_edit output shape) |

> These are the **authoring** schemas (referenced as `<package>/schemas/…` in the docs). The runtime **transport** schema `activity-output.schema.json` (the full `ActivityAgentOutput` sent to the frontend) lives at the repo root `schemas/` — it's runtime-maintained and read-only to activities, so it is intentionally not part of this authoring bundle.

## VS Code wiring

Add to `.vscode/settings.json` in your activity workspace:

```jsonc
{
  "json.schemas": [
    {
      "fileMatch": ["activities/*/manifest.json"],
      "url": "./packages/freedeepagents-activity-builder/schemas/manifest.schema.json"
    },
    {
      "fileMatch": ["activities/*/runtime.json"],
      "url": "./packages/freedeepagents-activity-builder/schemas/runtime.schema.json"
    },
    {
      "fileMatch": ["activities/*/card_templates/*.json", "!**/*.vars.json"],
      "url": "./packages/freedeepagents-activity-builder/schemas/card-template.schema.json"
    },
    {
      "fileMatch": ["activities/*/card_templates/*.vars.json"],
      "url": "./packages/freedeepagents-activity-builder/schemas/card-vars.schema.json"
    }
  ]
}
```

## Programmatic validation

```python
import json, jsonschema

schema = json.load(open("packages/freedeepagents-activity-builder/schemas/manifest.schema.json"))
manifest = json.load(open("activities/my-activity/manifest.json"))
jsonschema.validate(manifest, schema)
```

## Authority chain

The **`tools/activity_verifier.py`** in this package is the source of truth — it implements the same rules these schemas describe, plus cross-file checks (e.g. each card template has a sibling `.vars.json`). If a schema and the verifier disagree, the verifier wins; please file a bug.

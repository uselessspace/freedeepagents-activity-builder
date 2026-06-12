# Example: Card-only with typed-KV

Use this when the activity needs durable state but not a custom frontend.

> `checklist-coach` below is an illustrative placeholder id. It shows the contract shape — what fields your own `data.schema.json` holds is entirely your design.

```text
activities/checklist-coach/
|-- data.schema.json
|-- card_templates/checklist.summary.json
|-- card_templates/checklist.summary.vars.json
`-- skills/checklist-coach-host/SKILL.md
```

`runtime.json`:

```json
{
  "llm_timeout_seconds": 120,
  "docker_timeout_seconds": 180,
  "data_schema_enabled": true
}
```

`data_schema_enabled: true` is what opts the activity into the typed-KV store; card-system mode is the runtime default.

`data.schema.json` keeps defaults at the top level:

```json
{
  "type": "object",
  "default": {
    "items": [],
    "last_summary": ""
  },
  "properties": {
    "items": {
      "type": "array",
      "x-auto-inject": true,
      "items": {
        "type": "object",
        "properties": {
          "id": {"type": "string"},
          "text": {"type": "string"},
          "done": {"type": "boolean"}
        },
        "required": ["id", "text", "done"]
      }
    },
    "last_summary": {"type": "string", "x-auto-inject": true}
  },
  "additionalProperties": false
}
```

Each key declares `x-auto-inject` explicitly: `true` injects it into the system
prompt every turn (the agent reads it directly); `false` keeps it hidden, read
on demand via `data_get(key)` (use it for secrets / large sets — the activity
must then declare `sse_debug_view` in `runtime.json`, see verifier check #15).

Prefer activity-owned tools such as `add_item(text)` and `complete_item(id)`
over asking the agent to compose raw `data_set` calls.

# Policy: generic runtime ↔ activity boundary

## Hard rule

Generic runtime code (`app/`, `schemas/`) stays activity-neutral.

## Verifier-enforced invariants

The verifier (`tools/activity_verifier.py`) scans for these patterns in `app/` / `schemas/` and refuses to ship if any are found:

| Pattern checked | Reason |
|---|---|
| `if activity_id == "<id>": ...` / `case "<id>":` switch / activity-id string literals | Branch on activity capability or skill content, not on id. |
| Activity-specific fields added to `schemas/activity-output.schema.json` | That schema is the shared transport contract; private fields live in each activity's `data.schema.json`. |
| Activity-specific UI behavior implemented in `app/` | Controls live in the activity's `site/` (Static Preview) or in card templates. |

## Where activity logic belongs

| Concern | Goes in |
|---|---|
| Decision policy, judging, generation, revision | `activities/<id>/skills/<id>-host/SKILL.md` (and its workflows/) |
| Card layouts | `activities/<id>/card_templates/*.json` + `*.vars.json` |
| Private state shape | `activities/<id>/data.schema.json` (typed-KV) |
| Static Preview frontend | `activities/<id>/site/` |

The runtime only sees activities through:
- `manifest.json` discovery
- `data.schema.json` validation on every typed-KV write
- `output.schema.json` validation (the shared one)
- Skills loaded via DeepAgents native `skills=` API

Never by name.

## Why this matters

Activities can be added, removed, or branched without touching the runtime. The runtime stays small, audit-able, and free of activity-cross-talk bugs.

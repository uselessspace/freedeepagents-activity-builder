# Data mode selection

Choose persistence independently from frontend mode. Card-only and Static
Preview activities may use any row below.

| Need | Data mode | Files/config |
|---|---|---|
| No durable business state | `none` | database disabled, `data_schema_enabled:false` |
| Growing/queryable records, filters, ordering, relations, transactions | `sqlite` (default) | `runtime.database` + `database/migrations/*.sql` |
| Small bounded state useful in most Agent turns | `typed-kv` | `data_schema_enabled:true` + `data.schema.json` |
| Prompt digest plus growing/queryable corpus or index | `hybrid` | both contracts |

## Retrieval is a separate decision

typed-KV provides validated key/value state and optional prompt projection. It
does not provide ranking, synonym expansion, evidence scoping, or corpus
search. Strong memory retrieval normally uses:

```text
small typed-KV digest (optional)
  -> Activity-owned search tool
  -> SQLite index/query store
  -> limited authoritative evidence read
  -> Activity-owned evidence validation
```

Use `retrieval_mode:indexed-evidence` when the Agent must plan queries and open
limited evidence. Keep permissions, deleted-state filtering, stable ranking,
and negative-claim validation in deterministic Activity code.

## Scope

- `instance`: one database per instance. Default and safest.
- `activity_type`: one database shared by all instances of the Activity Type in
  the same runtime plane. It may span users. Use trusted `ctx.user_id` for
  ownership filters unless the data is intentionally communal.

## Access

Choose `none`, `read`, or `read_write` independently for:

- `agent`: Activity @tools invoked during an Agent turn.
- `user`: deterministic Preview handlers invoked by an authenticated user.

These permissions control `ctx.database`; they never expose SQL to the Agent.
Domain and row-level authorization still belongs in the Activity interface.

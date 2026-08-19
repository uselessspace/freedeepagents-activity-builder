# Managed SQLite storage

Managed SQLite is the default store for new activities whose state grows or
needs deterministic queries. It is additive: existing activities without a
`runtime.database` block keep their current behavior and create no database.

## Runtime declaration

```json
{
  "data_schema_enabled": false,
  "database": {
    "enabled": true,
    "engine": "sqlite",
    "scope": "instance",
    "access": {
      "agent": "read_write",
      "user": "none"
    }
  }
}
```

The database is stored outside `/instance` and mounted only into the isolated
Activity Python Runner. DeepAgents command execution cannot see the file. The
runtime does not register `sql_query`, `sqlite_execute`, or any other generic
database tool.

## Schema migrations

Put ordered, immutable migrations in:

```text
database/migrations/0001_initial.sql
database/migrations/0002_add_index.sql
```

The runtime records applied filenames in `_fda_schema_migrations` and wraps
each migration atomically. Migration files must not contain `BEGIN`, `COMMIT`,
or `ROLLBACK`. Never edit an already released migration; add the next file.

## Activity interface

Use `ctx.database` only inside `make_tools(ctx)` / `make_handlers(ctx)`
closures. It is `None` when this caller has `none` access.

```python
@tool
def add_note(content: str) -> dict:
    """Add one note to this activity."""
    if ctx.database is None:
        return {"error": "database access is unavailable"}
    connection = ctx.database.connect()
    try:
        with connection:
            cursor = connection.execute(
                "INSERT INTO notes(content, owner_id) VALUES (?, ?)",
                (content, ctx.user_id),
            )
        return {"ok": True, "note_id": cursor.lastrowid}
    finally:
        connection.close()
```

Rules:

- expose domain tools/handlers, never raw SQL tools;
- never accept SQL text from Agent/user parameters;
- always use SQLite placeholders for values;
- close each connection before the tool/handler returns;
- do not retain `ctx.database` across calls or background jobs;
- never return `ctx.database.path` or copy the database into `/instance`;
- for `activity_type` scope, include ownership predicates based on trusted
  `ctx.user_id` unless shared rows are intentional;
- one user intent maps to one write tool, even when it also updates typed-KV or
  a derived index.

Read-only access opens SQLite in OS-level `mode=ro` and enables
`PRAGMA query_only=ON`. Write access enables WAL, foreign keys, a busy timeout,
and transactional context-manager behavior.

## typed-KV coexistence

SQLite content is never injected into the system prompt. Add typed-KV only for
small bounded state that should be visible on most turns—for example a compact
archive digest, selected project, or recent-item pointers. Keep the corpus and
queryable records in SQLite.

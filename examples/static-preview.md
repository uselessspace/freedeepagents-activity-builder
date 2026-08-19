# Example: Static Preview activity

Use this shape when cards alone are not enough and the activity needs a
persistent inspectable surface.

> `project-map` below is an illustrative placeholder id. It shows the contract shape (manifest modules + DSL boundary + `site/dist/`) — what your SPA renders (dashboard, graph, canvas, game, timeline…) is entirely your design.

## File shape

```text
activities/project-map/
|-- manifest.json          # includes dsl_builder_module, optional tools_module
|-- runtime.json           # classified SQLite / typed-KV / hybrid mode
|-- database/migrations/   # default SQLite schema (when enabled)
|-- data.schema.json       # optional Prompt-aware state (typed-KV / hybrid)
|-- preview_actions.json   # optional SPA -> standard Agent turn allowlist
|-- AGENTS.md              # thin entrypoint
|-- dsl_builder.py         # build(instance_dir) -> SPA DSL dict
|-- tools.py               # optional make_tools(ctx)
|-- card_templates/
|-- skills/project-map-host/SKILL.md
`-- site/
    |-- package.json
    |-- src/
    `-- dist/index.html    # produced by npm run build / install flow
```

## Manifest shape

```json
{
  "activity_type_id": "project-map",
  "name": "项目地图",
  "description": "把用户输入的项目、任务和依赖整理成可交互地图。",
  "model": "deepseek:deepseek-v4-flash",
  "skill_sources": ["skills"],
  "entrypoint": "AGENTS.md",
  "input_modes": ["text"],
  "tools_module": "tools",
  "dsl_builder_module": "dsl_builder"
}
```

## Flow

1. The agent emits cards for turn feedback and uses the classified data mode.
2. Activity tools update user-semantic state, such as `add_task` or
   `link_dependency`.
3. `dsl_builder.py` reads an Activity-maintained projection from instance files;
   direct database reads/writes go through Activity handlers/tools with
   `ctx.database`.
4. The SPA fetches `/preview/project-map/<instance_id>/api/dsl.json` and renders
   the dashboard, graph, canvas, timeline, or form workflow.
5. Optionally, after a successful activity operation, the backend calls
   `ctx.emit_preview_navigation({...})`; the SPA receives `preview_navigate` on
   the same DSL stream and selects the relevant activity view or business
   object. This event is transient, user-scoped UX—not browser automation,
   durable state, or a manifest capability.
6. Directory verification keeps the finished project at `activities/<id>/` for
   FDA Dev Client / `fda-dev` directory sync.

## Optional recording and ASR

If this SPA records audio, add `"asr"` to `capabilities` and choose the path
that owns the next decision:

- The SPA needs an immediate editable transcript: `POST api/asr` as multipart
  `audio` with an `Idempotency-Key`. It returns text and usage without creating
  an Agent turn.
- The Agent needs the recording: `POST api/upload`, then put the returned
  same-instance `resource_ref` in the Agent turn's `attachment_refs`. The
  runtime copies it into that turn as `file_0`; the Agent calls
  `transcribe_audio(source_file_id="file_0")`.

Use `apiUrl()` for both endpoints. The preview gateway supplies trusted
identity and billing attribution; the SPA must not send `user_id` or ASR
provider credentials. Detailed request examples:
[preview-asr.md](../references/preview-asr.md) and
[preview-agent-turns.md](../references/preview-agent-turns.md).

## Boundary

- Frontend code stays inside `activities/<id>/site/`; the activity ships only static assets — no backend services of its own.
- Activity-private data lives in the classified store. The SPA reads private DSL
  projections and calls domain handlers; it never receives SQL or a database path.
- Activity decisions stay in the activity's host SKILL.md + tools.py; generic runtime code remains activity-neutral.
- Agent navigation payload semantics stay in the activity; durable selection or
  workflow state still belongs in the Activity store and DSL.

# Example: Static Preview activity

Use this shape when cards alone are not enough and the activity needs a
persistent inspectable surface.

> `project-map` below is an illustrative placeholder id. It shows the contract shape (manifest modules + DSL boundary + `site/dist/`) — what your SPA renders (dashboard, graph, canvas, game, timeline…) is entirely your design.

## File shape

```text
activities/project-map/
|-- manifest.json          # includes dsl_builder_module, optional tools_module
|-- runtime.json           # data_schema_enabled: true (card-system mode is implicit)
|-- data.schema.json       # typed-KV business data
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

1. The agent emits cards for turn feedback and uses typed-KV for durable data.
2. Activity tools update user-semantic state, such as `add_task` or
   `link_dependency`.
3. `dsl_builder.py` reads `data.json` and returns the private DSL consumed by
   `site/`.
4. The SPA fetches `/preview/project-map/<activity_id>/api/dsl.json` and renders
   the dashboard, graph, canvas, timeline, or form workflow.
5. Optionally, after a successful activity operation, the backend calls
   `ctx.emit_preview_navigation({...})`; the SPA receives `preview_navigate` on
   the same DSL stream and focuses the relevant item. This event is transient,
   user-scoped UX—not durable state or a manifest capability.
6. Packaging produces `.fda.tgz`; `bash <package>/tools/install-activity.sh <pkg>` rebuilds
   `site/dist/` when needed.

## Boundary

- Frontend code stays inside `activities/<id>/site/`; the activity ships only static assets — no backend services of its own.
- Activity-private state lives in `data.schema.json` and is read through the activity's `dsl_builder.py` output, not from `frontend-src/`.
- Activity decisions stay in the activity's host SKILL.md + tools.py; generic runtime code remains activity-neutral.
- Agent navigation payload semantics stay in the activity; durable selection or
  workflow state still belongs in typed-KV and the DSL.

---
name: activity-builder
description: >-
  活动构建第 3 步·实现。Brief + Classification 后 scaffold 并填写活动目录；业务逻辑
  不进入通用 runtime。Use after classification to implement FDA activity files
  without putting business logic in generic runtime code.
---

# Activity Builder

> **何时用**：Brief + Classification 都齐、要真正写文件时。Static Preview 前端完成后或 Card-only 实现完成后，都先交 `/activity-review`。

Own scaffold and implementation. Require both `Activity Brief` and
`Activity Classification` before changing files.

## Shared References

Use the package assets relative to this skill:

- `../../workflows/02-author-backend.md` for backend scaffold and host skill.
- `../../workflows/03-image-tooling.md` when `image_axis` is not `none`.
- `../../workflows/04-derive-frontend.md` when `frontend_axis` is
  `static-preview`.
- `../../references/user-upload.md` for end-user uploads; `../../references/preview-agent-turns.md`
  for structured SPA actions needing model understanding, Skills, planning, or multiple tools.
- `../../references/preview-asr.md` when the SPA needs a transcript immediately
  without creating an Agent turn; use upload + `attachment_refs` when the
  Agent must own the recording instead.
- `../../policies/capabilities.md` plus the capability-specific reference for
  every value in Classification `runtime_capabilities`.
- `../../references/asset-lifecycle.md` for replace/delete/durability semantics.
- `../../references/preview-navigation.md` for `agent-to-preview`.
- `../../references/handler-context-lifecycle.md` before work may outlive a tool/handler call.
- `../../workflows/06-verify-directory.md` for verification expectations.
- `../../workflows/07-migrate-existing.md` when the user wants to fork an
  existing activity.
- `../../references/card-block-types.md` — **read before writing cards**; it owns
  the 6 block schemas, form semantics, and form-vs-action decision.
- `../../references/card-system-tools.md` for the canonical
  `card_emit_template` / `artifact_emit` / `memory_add` tool signatures
  and a worked example.
- `../../policies/output-protocol.md` for the card-system transport contract.
- `../../policies/manifest-allowed-fields.md` for manifest field whitelist.
- `../../policies/runtime-boundary.md` and
  `../../policies/skill-layering.md` for hard boundaries.
- `../../references/store-mode-table.md` for persistent image URLs.
- `../../references/data-mode-selection.md` for SQLite/typed-KV/hybrid/none.
- `../../references/sqlite-storage.md` whenever Classification enables SQLite.

## Card-Only Build

Create or update only the activity folder:

- `activities/<activity_type_id>/manifest.json`
- `activities/<activity_type_id>/runtime.json`
- optional `activities/<activity_type_id>/data.schema.json` (typed-KV/hybrid only)
- `activities/<activity_type_id>/database/migrations/*.sql` (SQLite/hybrid only)
- `activities/<activity_type_id>/output.schema.json` (scaffolded `$ref` placeholder — leave as-is)
- `activities/<activity_type_id>/AGENTS.md`
- `activities/<activity_type_id>/skills/<activity_type_id>-host/SKILL.md`
- `activities/<activity_type_id>/skills/<activity_type_id>-cards/SKILL.md`
- `activities/<activity_type_id>/card_templates/*.json`
- `activities/<activity_type_id>/card_templates/*.vars.json`
- optional `activities/<activity_type_id>/tools.py`

The exact `card_templates/<activity_type_id>.welcome.json` file is mandatory.
It is persisted during server sync and displayed directly by the frontend, so
it must be fully static: no `{{...}}` placeholders anywhere. Its paired
`.welcome.vars.json` must declare zero variables (`properties: {}` and
`additionalProperties: false`).

Use card-system output, the classified data mode, and a thin `AGENTS.md`. Put business
policy in activity skills and supporting files. The scaffolded host and cards
Skills contain `TODO_ACTIVITY_AUTHOR` markers; replace every marker before
review or verification. A completed activity must not contain Builder/project
path placeholders or unresolved `<id>` placeholders.

## Static Preview Build

In addition to the Card-only files, create:

- `activities/<activity_type_id>/site/`
- `activities/<activity_type_id>/dsl_builder.py`
- optional `activities/<activity_type_id>/tools.py`

Set `manifest.dsl_builder_module` and optionally `manifest.tools_module`. Build
the frontend into `site/dist/`. The SPA consumes only its activity DSL from
`/preview/<activity_type_id>/<instance_id>/api/dsl.json`.

Route Static Preview UI decisions to `../activity-frontend/SKILL.md`.

For `agent-to-preview`, emit private navigation only after successful tools or
handlers; never encode its semantics in generic runtime or manifest fields.

## Tool Boundaries

When a third-party API, index, model, or private operation is needed, expose an
activity-owned tool whose name matches the user intent. Keep generic runtime
code activity-neutral.

SQLite exists only as ``ctx.database`` inside trusted Activity Python. Never
expose SQL/path tools or copy it into `/instance`; use parameterized domain operations.

Treat `ctx` as call-scoped. Finish every `ctx`-dependent operation before the
tool/handler returns. Persist only plain job data for later work; a resume
handler must use the fresh `ctx` passed to its own `make_handlers(ctx)` call.
Never retain `ctx`, `ctx.llm`, or bound `ctx.*` methods in globals, background
threads/tasks, queues, timers, or callbacks.

Agent-driven business interaction must call activity-owned `@tool` functions,
handlers, or backend APIs. After a successful operation,
`ctx.emit_preview_navigation(...)` may select an activity-private route, view,
or business object, but it must not encode browser clicks, focus, scrolling, or
DOM targets. Persist the result first and let the SPA render it from DSL/data.

## Done Criteria

Route to `../activity-review/SKILL.md`; any CONFLICT returns here. Then use
`../activity-verify/SKILL.md` for the directory gate. 若已登录 `fda-dev`，验收后转
`../activity-dev-cli/SKILL.md` 跑目录 sync/smoke。

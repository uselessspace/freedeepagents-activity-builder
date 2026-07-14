---
name: activity-builder
description: >-
  活动构建第 3 步·实现。在 Brief + Classification 都有之后，scaffold 并填活动文件
  （manifest / runtime.json / data.schema / AGENTS.md / host skill / card_templates，
  含 form 表单卡）。业务逻辑只进 activities/activity-id/，绝不碰通用 runtime（app / frontend-src / schemas）。
  Use after Activity Brief and Activity Classification exist to scaffold and
  implement FDA activity files without putting business logic in generic runtime code.
---

# Activity Builder

> **何时用**：Brief + Classification 都齐、要真正写文件时。写完交 `/activity-frontend`（仅 static-preview）或直接 `/activity-packager`。

Own scaffold and implementation. Require both `Activity Brief` and
`Activity Classification` before changing files.

## Shared References

Use the package assets relative to this skill:

- `../../workflows/02-author-backend.md` for backend scaffold and host skill.
- `../../workflows/03-image-tooling.md` when `image_axis` is not `none`.
- `../../workflows/04-derive-frontend.md` when `frontend_axis` is
  `static-preview`.
- `../../references/user-upload.md` when the preview SPA must let end-users
  upload + persist their own images / voice recordings (`POST api/upload`).
- `../../workflows/06-verify-and-ship.md` for verification expectations.
- `../../workflows/07-migrate-existing.md` when the user wants to fork an
  existing activity.
- `../../references/card-block-types.md` — **read before writing any
  `card_templates/*.json`**. Catalogs the 6 block types (`markdown` /
  `info` / `form` / `action` / `image` / `audio`) with field-level schema,
  `form_id` rules, FormField submit semantics, and the form-vs-action
  decision tree (when to use a multi-field form vs a row of action
  buttons).
- `../../references/card-system-tools.md` for the canonical
  `card_emit_template` / `artifact_emit` / `memory_add` tool signatures
  and a worked example.
- `../../policies/output-protocol.md` for the card-system transport contract.
- `../../policies/manifest-allowed-fields.md` for manifest field whitelist.
- `../../policies/runtime-boundary.md` and
  `../../policies/skill-layering.md` for hard boundaries.
- `../../references/store-mode-table.md` when image generation or editing
  needs persistent URLs.

## Card-Only Build

Create or update only the activity folder:

- `activities/<activity_type_id>/manifest.json`
- `activities/<activity_type_id>/runtime.json`
- `activities/<activity_type_id>/data.schema.json`
- `activities/<activity_type_id>/output.schema.json` (scaffolded `$ref` placeholder — leave as-is)
- `activities/<activity_type_id>/AGENTS.md`
- `activities/<activity_type_id>/skills/<activity_type_id>-host/SKILL.md`
- `activities/<activity_type_id>/card_templates/*.json`
- `activities/<activity_type_id>/card_templates/*.vars.json`
- optional `activities/<activity_type_id>/tools.py`

The exact `card_templates/<activity_type_id>.welcome.json` file is mandatory.
It is persisted during server sync and displayed directly by the frontend, so
it must be fully static: no `{{...}}` placeholders anywhere. Its paired
`.welcome.vars.json` must declare zero variables (`properties: {}` and
`additionalProperties: false`).

Use card-system output, typed-KV state, and a thin `AGENTS.md`. Put business
policy in activity skills and supporting files.

## Static Preview Build

In addition to the Card-only files, create:

- `activities/<activity_type_id>/site/`
- `activities/<activity_type_id>/dsl_builder.py`
- optional `activities/<activity_type_id>/tools.py`

Set `manifest.dsl_builder_module` and optionally `manifest.tools_module`. Build
the frontend into `site/dist/`. The SPA consumes only its activity DSL from
`/preview/<activity_type_id>/<activity_id>/api/dsl.json`.

Route Static Preview UI decisions to `../activity-frontend/SKILL.md`.

## Tool Boundaries

When a third-party API, index, model, or private operation is needed, expose an
activity-owned tool whose name matches the user intent. Keep generic runtime
code activity-neutral.

## Done Criteria

Do not claim done from this skill. Route to `../activity-packager/SKILL.md` for
`.fda.tgz` packaging, install validation, and smoke evidence.

- **可选自审**：agent 定义写完/改完后，可先跑 `../activity-review/SKILL.md` 做语义体检（找指令自相矛盾、卡片编排不成立、承诺与能力错配等逻辑冲突）；有 CONFLICT 再回来改。不是完工硬门禁，打包流程不依赖它。

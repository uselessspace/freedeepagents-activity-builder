---
name: activity-frontend
description: >-
  活动构建第 4 步·前端（仅 static-preview）。给需要持久化富前端 / 强可视化交互的活动选 UI
  类型（dashboard / game / canvas / timeline / graph / pet / form workflow）并给 Static
  Preview 实现引导。card-only 活动不需要这一步。
  Use for FDA Static Preview activities that need a persistent frontend,
  stronger visual interaction, or frontend implementation guidance.
---

# Activity Frontend

> **何时用**：仅 `frontend_axis = static-preview` 或用户明确要更丰富前端时；card-only 活动跳过本步直接打包。

Use only when `frontend_axis` is `static-preview` or the user explicitly asks
for a richer frontend. Do not vendor external frontend skill source into this
package.

## UI Type Decision

Choose one primary UI type:

- `utilitarian dashboard` for operational review, comparison, queues, tables,
  filters, and repeated work.
- `game-like interactive` for rules, turns, progress, score, animation, and
  direct manipulation.
- `visual canvas` for spatial work, drawing, layout, whiteboard, maps, or
  inspectable generated media.
- `timeline` for sequences, schedules, history, milestones, or replay.
- `graph` for networks, trees, dependencies, flow, lineage, or knowledge maps.
- `pet/avatar` for avatar state, mood, growth, routines, or embodiment.
- `form workflow` for intake, review, approval, multi-step configuration, or
  structured decision capture.

## Static Preview Contract

- Source lives under `activities/<activity_type_id>/site/`.
- Build output is `activities/<activity_type_id>/site/dist/`.
- `vite.config.ts` must set `base: './'` so `/preview/<activity_type_id>/<activity_id>/`
  works.
- The frontend reads private activity DSL from `/api/dsl.json` and can subscribe
  to `/api/dsl/stream` for refreshes.
- `dsl_builder.py` owns the DSL shape by reading typed-KV data declared in
  `data.schema.json`.
- `tools.py` owns user-semantic writes when the preview needs interaction.
- Activity data semantics stay in `dsl_builder.py`, `tools.py`, and activity
  skills. Do not add frontend branches to `frontend-src/`.

## Frontend Decision

Before coding, write:

```markdown
## Frontend Decision
- ui_type:
- primary_view:
- dsl_shape:
- data_sources: data.schema.json keys and artifacts used
- interaction_tools: tools.py functions, or none
- refresh_model: initial fetch only / SSE / manual reload
- build_checks: npm run lint, npm run build, screenshots
```

## Implementation Guidance

Contract-wiring (unique to this step):

- Start from `../../frontend-base/` unless a local activity already has a better
  matching `site/` pattern.
- Keep `src/lib/types.ts` aligned with the dict returned by `dsl_builder.py`.
- Keep `src/lib/api-client.ts` as the single client for `/api/dsl.json` and
  `/api/dsl/stream`.
- Before editing derived shared files, read
  `../../policies/dont-touch-frontend-base.md`.

Visual stack (built in — no external skill to vendor): Tailwind for layout and
responsive states; motion sparingly for transitions/feedback/direct manipulation
(not decoration); lucide icons for actions; shadcn-style patterns for dialogs,
tabs, menus, inputs, sliders, and tables. The per-archetype polish budget,
motion example, and mobile/desktop screenshot check live in
[../../workflows/05-frontend-polish.md](../../workflows/05-frontend-polish.md).

## Optional Enhancers

Optional shadcn MCP examples or local UI skills may inspire patterns — they are
not hard dependencies and their source must not be copied into this package.

Route back to `../activity-builder/SKILL.md` for file integration, then to
`../activity-packager/SKILL.md`.

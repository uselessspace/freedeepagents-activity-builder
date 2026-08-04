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
- `vite.config.ts` must set `base: './'` so `/preview/<activity_type_id>/<instance_id>/`
  works.
- The frontend reads private activity DSL from `/api/dsl.json` and can subscribe
  to `/api/dsl/stream` for refreshes.
- Agent-driven semantic navigation arrives as a named `preview_navigate` event
  on that same stream; it may select an activity-private route, view, or
  business object, but must not encode clicks, focus, scrolling, or DOM
  targets. See `../../references/preview-navigation.md`.
- SPA actions that need the normal Agent runtime use structured Preview Agent
  turns plus an activity-root `preview_actions.json`; see
  `../../references/preview-agent-turns.md`. Direct handlers remain appropriate
  for deterministic data writes that do not need the Agent.
- A recording UI that declares `asr` chooses one public ASR path: direct
  multipart `POST api/asr` for an immediate transcript, or `api/upload` plus
  the Agent turn's `attachment_refs` when the Agent must receive current-turn
  `file_0`. See `../../references/preview-asr.md`.
- Agent business actions call activity-owned tools, handlers, or backend APIs;
  `preview_navigate` never substitutes for the business operation. Persist
  state first, then let DSL fetch/SSE refresh the SPA.
- `dsl_builder.py` owns the DSL shape by reading typed-KV data declared in
  `data.schema.json`.
- `handlers.py` exposes deterministic SPA reads/writes; `tools.py` exposes only
  the business operations the Agent must call. Shared operations use one plain
  implementation with thin adapters.
- Activity data semantics stay in `dsl_builder.py`, `tools.py`, and activity
  skills. Do not add activity-specific frontend branches to `app/`; keep them in the activity's `site/`.

## Frontend Decision

Before coding, write:

```markdown
## Frontend Decision
- ui_type:
- primary_view:
- dsl_shape:
- data_sources: data.schema.json keys and artifacts used
- interaction_tools: tools.py functions, or none
- recording_asr: none / direct transcript / Agent owns uploaded recording
- refresh_model: initial fetch only / SSE / manual reload
- agent_navigation: none / semantic route-view-object fields and resulting selection behavior
- build_checks: npm run lint, npm run build, screenshots
```

## Implementation Guidance

Contract-wiring (unique to this step):

- Start from `../../frontend-base/` unless a local activity already has a better
  matching `site/` pattern.
- Keep `src/lib/types.ts` aligned with the dict returned by `dsl_builder.py`.
- Keep `src/lib/api-client.ts` as the single client for `/api/dsl.json` and
  `/api/dsl/stream`.
- When navigation is enabled, consume the `navigation` value returned by
  `useDsl()`; validate private payload fields and keep duplicate/missing events
  harmless.
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

Route back to `../activity-builder/SKILL.md` for file integration, then run
`../activity-review/SKILL.md`; only a CONFLICT-free result enters packager.

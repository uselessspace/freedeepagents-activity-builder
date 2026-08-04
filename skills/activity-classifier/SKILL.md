---
name: activity-classifier
description: >-
  活动构建第 2 步·分类定型。读 Activity Brief，把活动定到几个技术轴：card-only 还是
  static-preview、要不要 tool / image、怎么打包交付。brief 写完、动手实现之前用。
  Use after an Activity Brief exists to classify an FDA activity into card-only
  or Static Preview, tool capability, image capability, and package delivery axes.
---

# Activity Classifier

> **何时用**：Brief 已写好、要定技术形态时 → 产出 Classification 后交 `/activity-builder`。

Read the `Activity Brief` and produce a fixed classification before build work.

## Axes

`frontend_axis`:

- `card-only` when generic cards, forms, files, and artifacts are enough.
- `static-preview` when the user needs a persistent rich view, canvas,
  dashboard, game-like interaction, timeline, graph, pet/avatar, map, or other
  specialized UI.

`tool_axis`:

- `runtime-only` when card-system, typed-KV, and declared runtime capabilities
  are sufficient.
- `activity-tools` when domain operations, third-party APIs, deterministic SPA
  writes, indexes, or private business logic need `tools.py` / `handlers.py`.

`runtime_capabilities` is an additive list drawn only from:
`image_generate`, `image_edit`, `tts_generate`, `read_document`, `asr`.
An empty list means no opt-in runtime tool.

`image_axis`:

- `none` for text/cards/artifacts only.
- `generate-only` for fresh images.
- `generate+edit-locked` when user/reference images must stay visually locked
  across edits.

`navigation_axis`:

- `none` when the Agent never needs to move the user's open preview.
- `agent-to-preview` when a successful Agent read/action should select an
  activity-private route, view, or business object in the current Static
  Preview. It must not encode browser clicks, focus, scrolling, or DOM targets.

`spa_interaction_axis` (Static Preview only):

- `none` for read-only DSL views.
- `handlers` for deterministic reads/writes that do not need an Agent.
- `agent-turns` for structured actions requiring model understanding, Skills,
  planning, or multiple tools.
- `mixed` when both classes of interaction exist. Direct `api/asr` remains a
  platform endpoint, not an Agent turn.

`delivery_target` defaults to `.fda.tgz`.

`runtime_mode` is derived from `frontend_axis`, not chosen independently:
`card-only` → `Card-only`, `static-preview` → `Static Preview`.

## Rules

- Card-only activities generate card templates, typed-KV schema, host skill, and
  optional activity-owned tools.
- Static Preview activities must generate `site/`, `dsl_builder.py`, and
  optional `tools.py`, then build to `site/dist/`.
- `agent-to-preview` requires `frontend_axis: static-preview`. It uses the
  runtime context helper and existing DSL SSE; it is not a manifest capability.
- Any non-`none` `spa_interaction_axis` requires `static-preview`.
- `runtime_capabilities` maps directly to `manifest.capabilities`; do not list
  `ctx.llm`, handlers, Preview Agent Turns, upload, or navigation there.
- **No half-preview mode.** Ship either a complete Card-only activity or a
  complete Static Preview one — never a partial frontend.
- External services and business decisions live in activity-owned tools and
  skills. Do not move activity policy into `app/` or
  `schemas/`.
- The classification fixes **which files the activity must ship** — it does not
  constrain the design. Do not pattern-match the new activity onto an existing
  one; design from the Brief, bounded only by the platform contract (cards
  validate, tools call cleanly, the web surface wires up).

## Output Contract

End this stage with a block named exactly:

```markdown
## Activity Classification
- frontend_axis:
- tool_axis:
- runtime_capabilities: []
- image_axis:
- navigation_axis:
- spa_interaction_axis:
- runtime_mode:
- delivery_target: .fda.tgz
- implementation_notes:
```

Then route to `../activity-builder/SKILL.md`.

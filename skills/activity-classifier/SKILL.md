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

- `zero-tool` for pure card/tool protocol plus typed-KV.
- `image-only` when only runtime image tools are needed.
- `external-api` when third-party services are required.
- `custom-tools` when domain operations need activity-owned Python tools.

`image_axis`:

- `none` for text/cards/artifacts only.
- `generate-only` for fresh images.
- `generate+edit-locked` when user/reference images must stay visually locked
  across edits.

`delivery_target` defaults to `.fda.tgz`.

`runtime_mode` is derived from `frontend_axis`, not chosen independently:
`card-only` → `Card-only`, `static-preview` → `Static Preview`.

## Rules

- Card-only activities generate card templates, typed-KV schema, host skill, and
  optional activity-owned tools.
- Static Preview activities must generate `site/`, `dsl_builder.py`, and
  optional `tools.py`, then build to `site/dist/`.
- **No half-preview mode.** Ship either a complete Card-only activity or a
  complete Static Preview one — never a partial frontend.
- External services and business decisions live in activity-owned tools and
  skills. Do not move activity policy into `app/`, `frontend-src/`, or
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
- image_axis:
- runtime_mode:
- delivery_target: .fda.tgz
- implementation_notes:
```

Then route to `../activity-builder/SKILL.md`.

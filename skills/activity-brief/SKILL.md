---
name: activity-brief
description: >-
  活动构建第 1 步·需求澄清。开发者有一个 FDA / FreeDeepAgents / DeepAgents 活动想法，
  但目标用户、核心循环、持久化、前端、图像、外部能力还没说清时用——把模糊点子问成结构化
  Activity Brief。动手 scaffold 之前的第一关。
  Use when a developer has an FDA / DeepAgents activity idea and the target
  user, core loop, persistence, frontend, image, or external-tool requirements
  are not explicit yet.
---

# Activity Brief

> **何时用**：刚有活动点子、需求还模糊时。只问清需求、不碰文件 → 产出 Brief 后交 `/activity-classifier`。

Own the first stage of building a FreeDeepAgents activity. Do not scaffold or
edit files until the brief is clear enough to classify.

## What To Clarify

Capture the smallest useful brief:

- `activity_type_id`: kebab-case candidate, or `unknown` if not chosen yet.
- `display_name`: human-facing activity name.
- `target_user`: who uses it and in what setting.
- `core_loop`: what the user provides, what the agent returns, and what repeats.
- `success_experience`: what a good first successful run feels like.
- `interaction_model`: card buttons, forms, uploads, chat, long-running view,
  or a combination.
- `frontend_need`: no dedicated frontend, static preview, visual canvas,
  dashboard, game-like interaction, timeline, graph, or other.
- `agent_navigation`: whether a successful Agent read/action should select,
  scroll, focus, or switch the user's open Static Preview; otherwise `none`.
- `image_need`: none, generate fresh images, or edit user/reference images.
- `external_capabilities`: APIs, databases, browser/search, files, payments,
  models, or other services.
- `persistence`: typed-KV fields, larger artifacts, secrets, indexes, or none.
- `delivery_target`: default `.fda.tgz` unless the user explicitly asks for a
  different target.

## Conversation Style

Ask compact questions. Prefer one grouped message with 5-7 concrete prompts
over a long questionnaire. If the user already gave enough information, infer
reasonable defaults and state them.

Good prompts:

- "Who is the user, and what do they click or type each turn?"
- "Is a card-only flow enough, or does this need a persistent visual view?"
- "Does the activity need generated images, edited images, third-party APIs, or
  long-term private data?"
- "After the Agent finds or changes something, should the open SPA navigate to
  that exact item automatically?"

## Output Contract

End this stage with a block named exactly:

```markdown
## Activity Brief
- activity_type_id:
- display_name:
- target_user:
- core_loop:
- success_experience:
- interaction_model:
- frontend_need:
- agent_navigation: none
- image_need:
- external_capabilities:
- persistence:
- delivery_target: .fda.tgz
```

Then route to `../activity-classifier/SKILL.md`.

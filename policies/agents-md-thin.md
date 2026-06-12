# Policy: activity AGENTS.md is a thin entrypoint

## Rule

`activities/<id>/AGENTS.md` ≤80 lines. Verifier issues a WARNING if larger.

## What it should contain

1. One-sentence activity description
2. Runtime Contract block：声明本活动跑在 **card-system 模式**（`runtime.json` 用 `data_schema_enabled = true` 启用 typed-KV），LLM 通过 `card_emit_template` / `artifact_emit` / `memory_add` 等工具表达副作用，业务字段通过活动 @tools 或 `data_*` 通用工具写入 `/instance/data.json`，完成时直接停
3. Pointer to `skills/<id>-host/SKILL.md` (where business logic lives) + 若有 cards skill 也指过去
4. Optional: input_modes reminder, completion definition pointer

## Where deeper content lives

Keep deeper content out of AGENTS.md by routing each concern to its proper home:

| Concern | Lives in |
|---|---|
| Phase transition rules | host skill `workflows/` |
| Card catalog with field definitions | host skill `references/` (or a dedicated `<id>-cards` skill) |
| Tool budget rules | host skill `policies/` |
| Strategy red lines | host skill `policies/` |
| Prompt templates | host skill `workflows/` |

## Reference shape (≤30 lines)

```markdown
# <ActivityName>

> 一句话讲清这个活动做什么。

## Runtime Contract

This activity runs in **card-system mode** with **typed-KV business data** (`runtime.json.data_schema_enabled = true`).

- Treat `current_instance_state.data` as activity-private state owned by the skills.
- Express all turn output by CALLING TOOLS — do NOT return any final JSON; anything outside a tool call is discarded.
- Emit cards via `card_emit_template(template_id, variables, assignment_id)`; persist business state through activity @tools (or generic `data_*` tools) into `/instance/data.json`; persist artifacts via `artifact_emit({...})`; persist memory via `memory_add(text)`.
- 图片产物由 runtime live-artifact pipeline 自动 surface——直接把 `image_generate` 返回的 `file_url` 填进卡片 ImageBlock 即可（无需 `artifact_emit`）。
- When done, just stop; the runtime assembles cards/state/artifacts/memory.

## 入口

业务策略全部位于 [skills/<id>-host/SKILL.md](skills/<id>-host/SKILL.md)。卡片协议位于 [skills/<id>-cards/SKILL.md](skills/<id>-cards/SKILL.md)（如有）。

## 输入

- input_modes: 见 manifest.json
```

## Why thin

The runtime treats `AGENTS.md` as the discovery entry — every coding agent loads it on first read. Big AGENTS.md = burned tokens for every new agent that touches the activity.

## Where fast-path content lives

Fast-path routing (greeting / smalltalk / single-shot intents) belongs in the host SKILL.md (its "Sub-routes" or routing table). AGENTS.md only routes to that skill and states the runtime contract — keeping it ≤80 lines and inexpensive for every coding agent that opens the activity.

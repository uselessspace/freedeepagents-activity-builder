---
name: activity-orchestrator
description: >-
  活动构建总入口（Codex 侧 router）。当开发者说"做/设计/搭建/开发一个 FDA、
  FreeDeepAgents 或 DeepAgents 智能活动"时进入，按 brief→classify→build→frontend→
  review→verify 链路调度。Claude Code 用户一般不直接调它。
  Use when a developer asks to build, design, scaffold, verify, or improve a
  new FDA / FreeDeepAgents intelligent activity from an idea.
---

# Activity Orchestrator (Codex entry)

> **何时用 `/activity-orchestrator`**：Codex 侧的活动构建总入口；Claude Code 用户直接用根 router 即可。

The full router contract lives in the package root [SKILL.md](../../SKILL.md).
Chain in order; the default deliverable is a verified
`activities/<activity_type_id>/` directory:

1. [../activity-brief/SKILL.md](../activity-brief/SKILL.md) — clarify the idea into a Brief.
2. [../activity-classifier/SKILL.md](../activity-classifier/SKILL.md) — fix the form axes.
3. [../activity-builder/SKILL.md](../activity-builder/SKILL.md) — scaffold + implement.
4. [../activity-frontend/SKILL.md](../activity-frontend/SKILL.md) — only for static-preview.
5. [../activity-review/SKILL.md](../activity-review/SKILL.md) — semantic conflict review.
6. [../activity-verify/SKILL.md](../activity-verify/SKILL.md) — deterministic directory gate.

When an authenticated FDA Dev Client session exists, continue through
[../activity-dev-cli/SKILL.md](../activity-dev-cli/SKILL.md) for directory sync
and a real smoke turn.

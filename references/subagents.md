# Subagents & the `write_todos` planner (opt-in harness knobs)

Two deepagents capabilities are **off by default** and opt-in per activity:
the `task` tool (subagent delegation) and the `write_todos` planner. Most
activities — fixed-card or single-tool turns — should leave both off. Reach
for them only when a turn is a genuinely multi-step pipeline.

## Subagents — the `subagents/` folder

An activity exposes the `task` tool **only** by declaring one or more
subagents. The convention mirrors skills (`skills/<name>/SKILL.md`):

```
activities/<id>/subagents/<name>/AGENT.md
```

No folder (or an empty one) → no `task` tool at all. Each `AGENT.md` is YAML
frontmatter plus a markdown body that becomes the subagent's system prompt:

```markdown
---
name: research-helper          # optional, defaults to the folder name
description: 主 agent 何时该委派给它（必填，是委派判断依据，写清边界）
model: deepseek:deepseek-v4-flash   # optional, defaults to manifest.model
tools: []                      # optional — see the table below
skills:                        # optional, activity skill source dirs
  - skills/some-skill
write_todos: false             # optional, expose write_todos to this subagent
---
You are a focused support subagent inside the same activity runtime.
Return concise findings or concrete file changes to the main agent. Do not
finalize the activity turn unless explicitly asked.
```

### Why subagents

A subagent runs in its **own clean context** — it does focused, bounded work
(targeted file analysis, verification, parallel research) and returns a concise
result without polluting the main agent's history. Use it when a subtask is
independent and would otherwise bloat the main turn. Do **not** use it for
direct final-output assembly, schema repair, or trivial reads — finish those in
the main agent.

### Tools a subagent gets

Sandbox built-ins (`ls`, `read_file`, `write_file`, `edit_file`, `glob`,
`grep`, `execute`) and any declared `skills` are **always** available — they are
injected by middleware, independent of the `tools` field. The `tools` field
only controls which of the activity's **business** tools the subagent inherits:

| `tools` value | Subagent gets |
|---|---|
| `[]` or omitted | only sandbox built-ins + skills — **clean context (default)** |
| `["image_generate", "add_memory"]` | built-ins + those named business tools (on demand) |
| `"*"` | built-ins + **all** main-agent business tools (escape hatch) |

Prefer the smallest set. An unknown tool name is a verifier/runtime error, not
a silent drop.

### Model

`model` defaults to `manifest.model` and is resolved through the same
OpenAI-compatible client the main agent uses. Override it (`provider:model`)
only when the subtask genuinely needs a different tier.

## `write_todos` — runtime.json opt-in

`write_todos` is one of the per-activity `runtime.json` knobs — see
[runtime-config.md](runtime-config.md) for the full field table.

```jsonc
// activities/<id>/runtime.json
{ "write_todos": true }
```

Default `false`: the planner tool is hidden from the model entirely. Enable it
only for activities whose typical turn is a complex multi-step pipeline (3+
meaningful steps with external evidence or artifact work). When on, usage is
still governed by a strict policy that discourages it for simple/fixed-card
turns. Authoritative list = `grep -l write_todos activities/*/runtime.json`.

For subagents, `write_todos` is gated separately via the `write_todos`
frontmatter flag in `AGENT.md` (default off, keeping the subagent context
clean).

## Where this is enforced

- `app/activity_subagents.py` — discovers and validates `subagents/`.
- `app/deepagents_runtime.py` — `TodoToolPolicyMiddleware` (the `write_todos`
  gate) and the harness profile (GP subagent disabled, so `task` is opt-in).
- `app/models.py` — `ActivityRuntimeConfig.write_todos`.

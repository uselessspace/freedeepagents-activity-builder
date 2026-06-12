# Policy: progressive-disclosure skill layering

## Rule

Every `SKILL.md` ≤120 lines. Detailed content moves to:

- `workflows/*.md` — multi-step procedures
- `policies/*.md` — red lines, invariants
- `references/*.md` — lookup tables, schemas, dictionaries
- `examples/*.md` — concrete templates
- `scripts/` — runnable helpers

`SKILL.md` keeps only:
1. activation conditions (who triggers, when)
2. input/output contract
3. routing table to deeper files
4. red-line reminders
5. minimum example to disambiguate routes

## Why

LLM working set stays small. Prompt cache hit-rate stays high. Reviewers can scan a skill in 30s. Deep content only loads when the agent actually opens that file.

## Anti-pattern (do NOT)

```markdown
---
name: weather-buddy-host
description: ...
---

# Weather Buddy Host

## Phase 1: 欢迎
当用户来时，先...
然后判断条件 X：
  如果是 A，则...
  （5 屏滚动）

## Phase 2: 主循环
（又 8 屏）
```

5 KB SKILL.md = burned context every turn.

## Correct shape

```markdown
---
name: weather-buddy-host
description: ...
---

# Weather Buddy Host

## Phase routing
| phase | workflow |
|---|---|
| welcome | [workflows/welcome.md](workflows/welcome.md) |
| playing | [workflows/playing.md](workflows/playing.md) |

## Tool budget
[policies/tool-budget.md](policies/tool-budget.md)

## Hard constraints
- Tool error → fix params and retry once; further retries surface to the user.
- Welcome / smalltalk fast-path emits a single card and stops; no external tool calls.
```

30 lines. Phases load on demand.

## Verifier check

`tools/activity_verifier.py` issues a WARNING for any SKILL.md > 120 lines without supporting files. If you see "large SKILL.md should move detailed policy into skill-local supporting files", split.

## ≤80 lines for activity AGENTS.md

Same idea but stricter — the activity's `AGENTS.md` should only route to skills, not be the policy archive itself. See [agents-md-thin.md](agents-md-thin.md).

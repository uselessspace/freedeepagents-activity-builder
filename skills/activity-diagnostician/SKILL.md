---
name: activity-diagnostician
description: >-
  独立工具·失败排查。当 FDA / FreeDeepAgents 活动的某个 turn 失败、用户贴了错误日志、或
  描述症状（"卡渲染不全" / "agent 一轮没回应" / "卡片重复" / "没生成图"）时用。三种入口
  （turn_id / 错误日志 / 症状）→ 匹配已知错误类 → 给出根因、修复位置和验证步骤。
  Use when an FDA / FreeDeepAgents activity turn failed, when the user pastes
  an error log, or when the user describes a symptom like "卡渲染不全" /
  "agent 一轮没回应". Routes the failure to a known error class and points at
  the concrete fix.
---

# Activity Diagnostician

> **何时用**：活动跑出问题要 debug 时——给 `turn_id` / 错误日志 / 症状描述任一即可。`/activity-smoke` 判定失败后通常转到这里。

Own the "turn failed — what went wrong" path. Each error class in
[references/error-classes.md](references/error-classes.md) maps a trace
signature to a root cause, a fix location, and the validation step that
confirms the fix.

## Input forms

Three accepted; pick the one with the most signal:

1. **`turn_id`** (preferred) — e.g. `4daad15531a247c9938b355f2eb1d25e`. Locate
   `runtime/instances/<activity_type_id>/<activity_id>/turns/<turn_id>/`; the
   `input.json` shows what the user sent and `trace.jsonl` shows what the
   runtime / LLM / tools did. Walk to [workflows/from-turn-id.md](workflows/from-turn-id.md).
2. **Error log / stack trace pasted by user** — the user copied a message like
   `BadRequestError(...)` or `OutputValidationError: ...`. Walk to
   [workflows/from-error-log.md](workflows/from-error-log.md).
3. **Symptom description** ("卡片重复 / agent 没反应 / 渲染丢字段") — read
   [references/error-classes.md](references/error-classes.md) row by row;
   each class lists a "user-visible symptom" hint. Match symptom → class →
   request a `turn_id` to confirm.

## Output

A short diagnosis with three sections:

```markdown
## Diagnosis
- Error class: <class id from error-classes.md>
- Root cause: <one sentence>
- Trace evidence: <quoted line(s) from trace.jsonl>

## Fix
- Edit `<exact file path>`: <what to change>
- Authoritative policy: `<path-to-skill-file> §<section>`

## Validation
- Run `<command>` and look for `<expected output>`
```

Don't propose more than one fix per turn — pick the highest-confidence class
and verify before moving on.

## When the class doesn't match

If `error-classes.md` has no row matching the symptom + trace, say so
explicitly and capture:

1. The exact error string from `trace.jsonl`'s first `*_error` event.
2. Activity id + a 10-line `input.json` excerpt.
3. Which existing policy / reference doc closest to the issue (so a follow-up
   PR can add a new error class row).

A "no class matched" outcome is a real outcome — better than guessing.

## Routes

- [workflows/from-turn-id.md](workflows/from-turn-id.md) — start from a turn id
- [workflows/from-error-log.md](workflows/from-error-log.md) — start from an error string
- [references/error-classes.md](references/error-classes.md) — the lookup table

## Companion skills

- After proposing a fix, route the user to `activity-verify` (static check) and
  then `activity-smoke` (real turn) before declaring the bug fixed.
- For repeated failures on the same turn, the fix often belongs in
  [`policies/llm-output-discipline.md`](../../policies/llm-output-discipline.md);
  cite it directly in the diagnosis.

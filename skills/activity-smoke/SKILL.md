---
name: activity-smoke
description: >-
  独立工具·端到端冒烟。确认装好的活动真能服务一个 turn——检查该 turn 的 trace.jsonl 里
  card_item / turn_completed / done 三个 SSE 事件齐不齐。装完活动、想确认它真能跑时用。
  不替你起 uvicorn、不伪造 LLM——你来驱动那一个 turn，它负责判定证据。
  Use to confirm an FDA activity actually serves a turn end-to-end after install.
  Specifies the evidence standard (card_item / turn_completed / done events in
  trace.jsonl) and ships a minimal parser.
---

# Activity Smoke

> **何时用**：活动装好后确认"真能跑出东西"。判定失败 → 带同一个 `turn_id` 转 `/activity-diagnostician`。

Dynamic verification. The smoke is "an installed activity successfully
served one user turn" — not "every code path works".

## Evidence standard

A turn is considered smoke-passing when its `trace.jsonl` contains at least
one of each of these SSE event types (assertable offline against the file):

| Event type | What it proves |
|---|---|
| `card_item` (non-fallback) | The activity emitted at least one real user-visible card. Cards whose payload matches the runtime zero-emit fallback signature (`assignment_id="runtime-zero-emit-fallback"` / `card.template="runtime.zero_emit_fallback"` / `card.meta.kind="zero_emit_failure"`) do **not** count — they indicate the activity emitted nothing and the runtime stepped in. |
| `turn_completed` | The turn reached its terminal state cleanly. |
| `done` | The runtime signed off the SSE stream (no abrupt termination). |

Any of these missing means the turn did not complete normally; route to
`activity-diagnostician` with the same `turn_id`.

## Driving the turn

The operator runs the activity manually in an environment that has:

- An FDA service (uvicorn + the runtime) reachable, OR
- `scripts/dev_smoke_card_system.py` for static prompt / loop-guard checks
  (does not exercise emit paths).

For a real end-to-end smoke:

1. Start the FDA service (`uvicorn app.main:app ...`).
2. Open the activity in the client and send a single user message.
3. The runtime writes the trace at
   `runtime/instances/<activity_type_id>/<activity_id>/turns/<turn_id>/trace.jsonl`.
4. Run the parser below against that file.

This skill deliberately stops short of automating step 1-2 *by itself*.
Different deployments have different start commands, ports, and LLM
credentials. The parser + the evidence standard are the portable core.

### Automated path: `fda-dev` (recommended when a dev runtime is reachable)

If a live dev runtime is reachable (the colleague's dev-client bundle ships a
pre-configured `fda-dev` CLI), drive steps 1-3 in ONE command instead of
manually starting uvicorn + clicking the client:

```bash
fda-dev --folder activities/<id> message --sync-first --new --smoke "<a representative user message>"
# stderr → SMOKE: PASS (card_item=1 turn_completed=1 done=1)  [exit 0]  /  SMOKE: FAIL ... [exit 1]
```

`--smoke` runs the turn and asserts **this skill's evidence standard** (real
`card_item` + `turn_completed` + `done`, fallback rule applied) — verdict to
stderr, exit non-zero on FAIL, no parser needed. All flags, the
`--pull-logs-on-error` → `/activity-diagnostician` path, and the server rate
limit are documented in
[../../references/dev-agent-cli.md](../../references/dev-agent-cli.md).

## Parser

Pure stdlib — runs under any Python 3.10+, including a plain `python3`
on PATH.

```bash
python3 <package>/skills/activity-smoke/scripts/parse-trace.py \
    <path>/runtime/instances/<activity_type_id>/<activity_id>/turns/<turn_id>/trace.jsonl
```

Output:

```
==> trace.jsonl summary
  card_item: 1
  turn_completed: 1
  done: 1
  llm_error: 0
  ...
==> Smoke: PASS  (card_item ≥ 1, turn_completed ≥ 1, done ≥ 1)
```

Or:

```
==> Smoke: FAIL
  missing: turn_completed
  first error: llm_error - BadRequestError ...
==> Route to activity-diagnostician with this turn_id.
```

## Combined output contract

```markdown
## Smoke
- turn_id: <id>
- card_item: <count>
- turn_completed: <count>
- done: <count>
- result: PASS / FAIL — <reason if FAIL>
```

## When to run

- After `activity-packager` installs a new package.
- After `activity-builder` applies a fix that the static `activity-verify`
  can't confirm (LLM behavior, prompt wording, turn boundary correctness).
- Periodically against deployed instances for regression catching.

## Hand-off

- `result: PASS` → record the line in Ship Verification.
- `result: FAIL` → route to `activity-diagnostician` with `turn_id`; the
  parser already pulled out the first error event for you.

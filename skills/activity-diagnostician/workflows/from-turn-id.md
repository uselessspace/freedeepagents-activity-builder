# Workflow — Diagnose from a turn id

Use this when the user says "看下 turn `<turn_id>`" / "this turn failed:
<id>" / pastes a turn id from the UI.

## Step 1 — Locate the turn directory

Trace files live at:

```
<repo>/runtime/instances/<activity_type_id>/<activity_id>/turns/<turn_id>/
  ├── input.json       # what the user submitted
  └── trace.jsonl      # one JSON event per line
```

If the user gave only `turn_id`:

```bash
find runtime/instances -maxdepth 5 -type d -name "<turn_id>" 2>/dev/null
```

Pick the path with `runtime/instances/<activity_type_id>/<activity_id>/turns/<turn_id>`
shape (the one with `input.json` next to `trace.jsonl`).

## Step 2 — Read input.json (10 lines is enough)

It tells you: the activity, the user text, and any files uploaded. This
contextualizes what the agent was *trying* to do.

## Step 3 — Find the first failure event in trace.jsonl

Common failure events (`event` field in each JSONL row):

| event | what it means |
|---|---|
| `llm_error` | The LLM provider returned an error (400 / 401 / 500 / timeout). Most common: DeepSeek strict-mode 400 → E1. |
| `chain_error` | A LangGraph chain step raised. Often a tool's pydantic input validation or a JSON-decode of a malformed tool call → E2 / E3. |
| `tool_error` | An individual tool returned `{"error": ...}`. Inspect the tool name + message → E6 / E7. |
| `turn_error` | Terminal turn failure surfaced to SSE. Final wrapper around one of the above. |
| `system_message_injected` followed by `card_item` with `template="runtime.zero_emit_fallback"` | E5 zero-emit fallback. |

```bash
grep -E '"event": "(llm_error|chain_error|tool_error|turn_error|system_message_injected)"' \
  runtime/instances/<activity_type_id>/<activity_id>/turns/<turn_id>/trace.jsonl | head -5
```

## Step 4 — Match the error string against `references/error-classes.md`

Pull the most stable substring from the error (e.g.
`"field 'anyOf': one of 'type', 'anyOf', '$ref' field is required"`) and
grep `references/error-classes.md` for it. The matching row gives you root
cause + fix location + validation step.

## Step 5 — Produce the diagnosis

Follow the output contract from [the skill entry](../SKILL.md#output):
three sections (`## Diagnosis`, `## Fix`, `## Validation`). Cite the matched
error class id (e.g. `E1`) and the authoritative policy section by full
relative path.

## Step 6 — Hand off

- If the fix is one localized file edit, propose the edit and route to
  `activity-verify` to confirm the static check passes.
- If the fix touches multiple files or changes the activity's interaction
  shape, route to `activity-builder` instead.
- For a fix that needs a real turn to confirm (LLM behavior, not just static),
  route to `activity-smoke` after the edit.

## When the trace doesn't have any of these events

The turn might have succeeded but produced an unexpected result. Inspect the
`card_item` payloads to see what actually rendered, and ask the user what
they expected versus what they saw. That's a symptom-based diagnosis — switch
to [from-error-log.md](from-error-log.md)'s symptom-matching approach.

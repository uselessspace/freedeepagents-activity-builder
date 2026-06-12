# Workflow — Diagnose from an error log / symptom

Use this when the user pastes an error message, a stack trace, or describes
the failure in words without a `turn_id`.

## Step 1 — Identify the most stable substring

Strip transient parts (timestamps, instance IDs, line numbers). Keep the
phrase that's likely to be identical across reproductions. Examples:

- `"field 'anyOf': one of 'type', 'anyOf', '$ref' field is required"`
- `"Extra inputs are not permitted"`
- `"image_edit requires object storage for source staging"`
- `"manifest.json has disallowed field"`

## Step 2 — Match against `references/error-classes.md`

```bash
grep -n "<stable substring>" \
  packages/freedeepagents-activity-builder/skills/activity-diagnostician/references/error-classes.md
```

The matching `E<n>` row is your diagnosis.

## Step 3 — Ask for a turn id (only if confirmation is needed)

If the error class is unambiguous (a clean match to one of the E-classes), skip
this. If multiple classes could match (e.g. a `chain_error` could be E2 or
E3), ask for the `turn_id` so you can pull the actual trace and disambiguate
via [from-turn-id.md](from-turn-id.md).

## Step 4 — Symptom-based fallback

If no error string is available, only a symptom description like "卡片渲染
不完整" / "agent 半天没回答" / "图片没出来":

| Symptom | Likely class |
|---|---|
| Agent doesn't reply / generic "AI 本轮未能给出有效回答" card | E5 (zero-emit fallback) or E1 (strict-mode rejection) |
| Same card rendered twice / live-update not working | `policies/llm-output-discipline.md §1` (assignment_id) — usually not E-class |
| Card missing a field / showing `{{var}}` literal | E3 (StrictModel) or template variable not passed |
| Image URL 404 / image not showing | E6 or wrong `read_url` field |
| Static Preview blank page | E10 (dsl_builder missing / 404) |
| "verifier ERROR" output | E8 (whitelist) or E9 (data.schema default) |

Ask for a turn id or verifier output to confirm before proposing a fix.

## Step 5 — Produce the diagnosis

Same output contract as [the skill entry](../SKILL.md#output). State the
class with a confidence level if you're inferring from a symptom rather than
a concrete trace.

## Step 6 — Hand off

Same as [from-turn-id.md](from-turn-id.md#step-6--hand-off).

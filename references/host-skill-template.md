# Host Skill authoring contract

The executable scaffold source is
`templates/activity-template/skills/template-activity-host/SKILL.md`. After
scaffolding, edit the copy under `activities/<id>/skills/<id>-host/SKILL.md`;
do not copy Builder-only paths into the activity.

## Required shape

- Keep the entrypoint at 120 lines or fewer and use it as the single business
  intent/phase router.
- Route detailed generation, judging, revision, and multi-step procedures to
  skill-local `workflows/`, `policies/`, or `references/` files.
- Keep card presentation and literal `assignment_id` values in the mandatory
  sibling `<id>-cards` Skill.
- Remove every `TODO_ACTIVITY_AUTHOR` marker before review and verification.
- Use only activity-runtime paths such as `/activity/skills/...` and
  `/instance/workspace/...`; the Builder package is not mounted in the activity
  Docker.

## Runtime state

- `current_instance_state.data.phase` and the counters/`last_*_id` values are
  runtime-derived from emitted cards/artifacts and are not business writable.
- If `data.schema.json` declares a business `phase`, that typed-KV value is the
  activity tool guard/router authority. The activity must keep its meaning
  aligned with card `meta.phase` deliberately.
- `x-auto-inject: true` business fields are already in the prompt; hidden
  fields require `data_get(key)`.
- `current_datetime` is the only reliable wall-clock input for resolving
  relative dates. Activities that do not interpret relative dates can ignore it.

## Output discipline to write locally

The finished host Skill must state, in activity-local prose:

1. User-visible output uses `card_emit_template`, `card_emit`, or
   `artifact_emit`; the LLM does not return final JSON.
2. Fixed cards reuse the literal IDs listed in the cards Skill.
3. Business writes prefer activity @tools, with `data_*` only for fields that
   have no business wrapper.
4. Image tool artifacts are auto-surfaced; only their `file_url` enters a card.
5. Terminal routes call `mark_status` once and stop.
6. Any multi-step route defines a `Turn boundary` saying whether this turn
   completes or deliberately awaits user input.

Do not replace these points with a link to a Builder policy: that link will be
unreadable after the activity is installed.

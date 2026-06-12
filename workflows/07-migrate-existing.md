# Workflow 07 (alternate path): Branch / retro-fit an existing activity

Use this **instead of** the brief→classify→build→package chain (workflows 02-06) when the user wants to fork an existing activity in their repo (`ls activities/` to see what exists) into a new id, OR retro-fit one with a new feature without rebuilding from scratch.

## Decision: branch or in-place

| Want to | Pick |
|---|---|
| Keep the original AND make a variant | **branch** |
| Add a feature to the original (no fork) | **in-place** |
| Unsure | **branch** (safer; no risk to deployed instances of the original) |

## Branch path

```bash
bash <package>/tools/branch-activity.sh <source-id> <new-id> "<New Display Name>"
```

The script:
1. `cp -R activities/<source-id>/ activities/<new-id>/`
2. Substitutes `<source-id>` → `<new-id>` in file contents
3. Substitutes the source's display name → new display name (if provided)
4. Renames files/dirs containing `<source-id>` (skill folders, card filenames)
5. Detects existing frontend assets and prints reminder to review Static Preview status

After branching:

1. **Edit `description`** in `activities/<new-id>/manifest.json` — don't leave duplicate descriptions.
2. **Customize host skill workflows** (`activities/<new-id>/skills/<new-id>-host/workflows/*.md`) — the source semantics are still embedded.
3. **Edit card_templates content** — file names are renamed, but text inside still mentions the source domain (e.g. the source activity's wording leaking into your new branch).
4. **Static Preview only**: `bash <package>/tools/derive-frontend.sh <new-id>` — gives the branch a fresh frontend at `activities/<new-id>/site/` (don't share the source's `activities/<source-id>/site/`).
5. Run [06-verify-and-ship.md](06-verify-and-ship.md).

## In-place path

Editing the original. **Verify after EVERY change.**

### Add image capability

1. `manifest.json`: add `"capabilities": ["image_generate"]` (or `+ "image_edit"`)
2. host skill: incorporate [03-image-tooling.md](03-image-tooling.md) decision tree
3. `data.schema.json`: add typed-KV fields such as `reference_artifact_id` +
   `reference_url` (if locked-reference axis)
4. card_templates: add `<id>.image_failed.json` + `.vars.json` (use [../references/card-block-types.md](../references/card-block-types.md))

### Card-only → Static Preview upgrade

**Don't** do this in-place. It's effectively half a new activity. Branch first, upgrade the branch, test, then deprecate the original.

### Add a new skill_source

1. Write `activities/<id>/skills/<source-name>/SKILL.md` (≤120 lines) + supporting files
2. Add `"skills/<source-name>"` to `manifest.json`'s `skill_sources` array
3. Update host SKILL.md's tool budget / routing table
4. Re-verify + smoke

## Compatibility invariants (preserve for deployed instances)

For in-place edits, keep these stable so existing instances keep working:

| Field / shape | Preservation rule |
|---|---|
| `manifest.activity_id` | keep the existing id (routing + instance dirs depend on it) |
| `output.schema` field types | keep the same types the frontend renderer expects |
| `data.schema.json` typed-KV field types | keep types stable so existing `data.json` values validate |
| Optional typed-KV fields | leave optional unless you also migrate existing values |

Safe additions: new optional typed-KV fields, new card templates, new phase enum
values, new `skill_sources`. Branch into a new id instead of in-place when the
required change conflicts with the table above.

## Hand-off

```
Activity migrated (<branch|in-place>) — source: <source-id>, target: <new-id-or-same>.
Changes: <one-line summary>.
Proceeding to 06-verify-and-ship.md.
```

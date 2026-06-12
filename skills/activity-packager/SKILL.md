---
name: activity-packager
description: >-
  活动构建第 5 步·打包交付。把实现好的活动打成 .fda.tgz、装进真 repo、收集 verifier +
  smoke 证据。实现（和前端，如有）完成后用，是工作流的最后一步。
  Use after FDA activity implementation to create the .fda.tgz package, install
  it in a real repo, and collect verifier plus smoke-test evidence.
---

# Activity Packager

> **何时用**：活动实现完要出包时（含前端，若有）。单独校验/冒烟/排错另有 `/activity-verify` `/activity-smoke` `/activity-diagnostician`。

Own final delivery. Default output is `.fda.tgz`.

## Package

From the FreeDeepAgents repo root, package the activity:

```bash
bash <package>/tools/pack-activity.sh <activity_type_id>
```

Use the produced `dist/<activity_type_id>-*.fda.tgz` unless the repository's pack
script reports a different path.

## Verify Install

Install the package into a real FDA repo:

```bash
bash <package>/tools/install-activity.sh <pkg>
```

The install must restore `activities/<activity_type_id>/`, rebuild Static Preview
assets when needed, and leave the activity runnable.

## Required Checks

- Run the activity verifier and fix every ERROR.
- Run the offline testkit smoke:
  `python <package>/testkit/fda_testkit.py activities/<activity_type_id>`
  (no platform repo needed; see [../../testkit/README.md](../../testkit/README.md)).
- Use `../../references/output-validation.md` for trace review and offline
  output validation when a smoke run looks wrong.
- For Card-only activities, smoke test a turn and capture `card_item`,
  `turn_completed`, and `done`.
- For Static Preview activities, also verify
  `/preview/<activity_type_id>/<activity_id>/` and
  `/preview/<activity_type_id>/<activity_id>/api/dsl.json`.
- For image activities, verify `manifest.capabilities`, persistent image URLs,
  and card image blocks.
- Acknowledge any warnings with a decision.

## Ship Verification

End with a `## Ship Verification` block. Its **exact format is owned by**
[workflows/06-verify-and-ship.md](../../workflows/06-verify-and-ship.md) Step 6 —
use that block verbatim (Verifier / Testkit smoke / Runtime setup-build / E2E
smoke / Warnings acknowledged / Files changed). Don't invent a second format.

Completion rule (also from workflow 06):

- `Verifier` (0 ERROR + the `scanned N` line) and `Testkit smoke` are **always
  required** — both run with no platform repo.
- The runtime steps (setup-build, E2E smoke) need the platform runtime. If you
  have it, paste the evidence. **If you don't, record "deferred to maintainer
  runtime smoke" on those lines** — that is a valid completion state for an
  external developer, not a blocker. The maintainer fills them on install.
- Only a *required* line that can't run (verifier / testkit) is a real blocker —
  then state it and don't call the package ready.

# Workflow 06: Verify the development directory (MANDATORY)

This is the terminal gate for the default workflow. The deliverable is the
finished `activities/<activity_type_id>/` directory used by FDA Dev Client and
`fda-dev --folder`.

## Step 0: Close semantic conflicts

Run `skills/activity-review/SKILL.md`. Any CONFLICT returns to
activity-builder and must be reviewed again after the fix. Record accepted
SMELL/NOTE items in Development Verification.

## Step 0.5: Resolve the project Python

Follow [`../references/python-environment.md`](../references/python-environment.md).
Reuse a compatible `<project-root>/.venv`; if none exists, create it there with
the target runtime's Python minor version. For the current FDA target, use the
bundled domestic-mirror bootstrap when a compatible interpreter is missing.
Do not write into the activity directory or a separate plugin cache. Replace
`<project-python>` with that environment's interpreter. `<runtime-python>` is
the target FDA repository's fully provisioned interpreter and is only needed
by the strict check.

## Step 0.6: Resolve Node for Static Preview only

Card-only activities skip this step. When `site/package.json` exists, follow
[`../references/node-environment.md`](../references/node-environment.md): reuse
Node 20 or 22 with npm 10, preferring Node 20 to mirror the current runtime.
When it is missing, announce and run the bootstrap's explicit Node option; it
uses a configured domestic mirror and a project-local `.fda-tools/` runtime.
Record executable paths, versions, and reused/selected state. Do not silently
install or replace a global Node runtime.

## Step 1: Run the verifier

```bash
<project-python> <builder-root>/tools/activity_verifier.py <project-root>
```

Pass `<project-root>` explicitly and keep complete stdout. Do not pipe through
`grep`: filters hide shared-runtime errors, the `scanned N activities` line,
and the verifier exit code.

- `ERROR` or exit 1/2 → block completion.
- `WARNING` → acknowledge with a decision.
- Exit 0 with the full summary → continue.

Fix one causal class at a time using
[`../policies/fix-loop.md`](../policies/fix-loop.md) and
[`../references/verifier-checks.md`](../references/verifier-checks.md).

## Step 2: Check activity tool schemas

When `manifest.tools_module` is set, run with the target FDA repo environment:

```bash
<runtime-python> <builder-root>/skills/activity-verify/scripts/strict-tool-schema-check.py \
  --activity <activity_type_id>
```

If no platform repo/runtime dependencies are available, record this command as
covered by the offline testkit in Step 3; do not install an old LangChain major
just for this check.

## Step 3: Run the offline testkit

```bash
<project-python> <builder-root>/testkit/fda_testkit.py activities/<activity_type_id>
```

It runs `make_tools(ctx)` and `dsl_builder.build()` against schema-validated
temporary data and rejects strict-mode-illegal tool schemas. This check is
always required, including when modules legitimately report `skipped`.

## Step 4: Build Static Preview locally

Card-only activities skip this step. Static Preview activities run:

```bash
cd activities/<activity_type_id>/site
node --version
npm --version
if [ -f package-lock.json ]; then npm ci; else npm install; fi
npm run lint
npm run build
```

Confirm local `site/dist/index.html`. It may remain in the development directory
as evidence, but FDA source sync excludes generated `dist/` and `node_modules/`;
`fda-dev --sync-first` rebuilds Static Preview server-side as needed. Do not
package or treat either generated directory as uploaded source.

## Step 5: Add live dev evidence when available

Point FDA Dev Client and `fda-dev` at the activity directory. Start read-only:

```bash
fda-dev --folder activities/<activity_type_id> doctor
fda-dev --folder activities/<activity_type_id> status
fda-dev --folder activities/<activity_type_id> sync --dry-run
```

If `activityHasPriorSync=false`, stop and ask the user to complete the first
upload in FDA Dev Client. Otherwise, when live testing is authorized:

```bash
fda-dev --folder activities/<activity_type_id> message \
  --sync-first --new --smoke --pull-logs-on-error \
  "<representative input>"
```

PASS requires a real non-fallback `card_item`, `turn_completed`, and `done`.
When the CLI/runtime is unavailable, the local development directory can still
be handed off after Steps 0–4; record live smoke as deferred, not passed.

## Step 6: Write Development Verification

```markdown
## Development Verification

- **Activity directory**: <absolute project-root>/activities/<id>
- **Builder bundle**: <absolute package path> · version <plugin version>; no mixed checkout/cache assets
- **Project Python**: <absolute interpreter path> · <version> · <reused / created>
- **Frontend Node**: <not applicable / absolute node + npm paths · versions · reused / selected>
- **Semantic review**: CONFLICT 0; accepted SMELL/NOTE: <list + reason, or "none">
- **Verifier**: 0 ERROR / <n> WARNING; full output: <paste including scanned line>
- **Strict-tool schema**: <m tools ok / covered by testkit / not applicable>
- **Testkit smoke**: <command> → <paste result line>
- **Frontend build**: <not applicable / npm ci or npm install; lint + build passed; site/dist/index.html exists>
- **FDA Dev Client / fda-dev**: <events and result / deferred: first GUI upload required / unavailable>
- **Warnings acknowledged**: <reason or "none">
- **Files changed**: <git diff --stat>
- **development-ready**: yes
```

Do not set `development-ready: yes` unless Steps 0–4 pass. Live evidence is
required only when the authenticated dev runtime is available and the first
GUI upload exists; otherwise explain the exact deferred state.

# Workflow 06: Verify and ship (MANDATORY)

This is the **terminal gate**. The activity is shippable only after semantic
review reports zero CONFLICT and a `## Ship Verification` block contains the
required verifier + smoke evidence (see step 6).

## Step 0: Close semantic conflicts

Run `skills/activity-review/SKILL.md` against the finished activity definition.
Any CONFLICT returns to activity-builder and must be reviewed again after the
fix. SMELL/NOTE findings may be accepted with a short reason in Ship
Verification; this is an in-session semantic check, not a platform API call.

## Step 1: Run the verifier

```bash
python3 <package>/tools/activity_verifier.py <project-root>
```

Always pass `<project-root>` explicitly and keep the complete stdout. Do not
pipe the release-gate invocation through `grep`: filtering hides generic-runtime
errors and the required `scanned N activities` line, and without `pipefail` the
pipeline exit code belongs to `grep` rather than the verifier.

Parse the output:
- Lines starting `ERROR ` → BLOCK ship
- Lines starting `WARNING ` → don't block but must be acknowledged in the Ship Verification block

Exit code: `0` if no errors, `1` if verification found errors, `2` if the
invocation itself is invalid (for example Python <3.10 or zero activities found).
`tools/pack-activity.sh` reruns this same full-project command and refuses to
create an archive on any non-zero result; the explicit Step 1 run remains
required because its complete stdout belongs in Ship Verification.

## Step 2: Fix one causal class at a time

See [../policies/fix-loop.md](../policies/fix-loop.md). Identical mechanical
instances of one cause may be batched; do not mix unrelated fixes because
verifier errors interact and you will lose the causal signal.

| Common ERROR | Cause | Fix |
|---|---|---|
| `manifest.json: disallowed field: foo` | non-whitelist field | delete the field, or move the value into `data.schema.json` if it's business state |
| `card_templates ... missing vars` | `*.json` without sibling `*.vars.json` | add the vars file (or delete orphan template) |
| `generic runtime hardcoded activity` | `app/`/`schemas/` references the activity id | move logic into `activities/<id>/skills/` |
| `skills= self._skill_sources` | `app/runner/` stopped using DeepAgents native loading | restore `skills=self._skill_sources(manifest)` |
| `tools_module ... make_tools` | manifest points at a missing or malformed activity tools module | add `tools.py` exporting `make_tools(ctx)` or remove the field |
| `dsl_builder_module ... build` | Static Preview builder missing or malformed | add `dsl_builder.py` exporting `build(instance_dir)` |
| `data.schema.json missing top-level default` | typed-KV defaults placed under `properties.*.default` | move initial values into the schema's top-level `default` |

Full reference: [../references/verifier-checks.md](../references/verifier-checks.md).

## Step 3: Prepare frontend runtime cache/build when needed *(platform-repo / install-side)*

> **External developers without the platform repo: skip this step** — it needs
> an FDA repo checkout + Docker and is run by the installer of your `.fda.tgz`.
> Card-only activities never need it. For local Static Preview UI work,
> `npm run build` in `site/` suffices; mark this line "deferred to maintainer".

Before smoking, the installer makes sure the frontend dependency cache is warm and Static Preview assets are built:

```bash
bash <package>/tools/setup-runtime.sh <your-id>
```

The script is idempotent and prewarms `runtime/sandbox_cache/node_modules/<id>/` when `site/package.json` is newer than the cache's `.fda-ok` sentinel. For Card-only activities with no `site/`, it returns immediately.

For packaged activities, `bash <package>/tools/install-activity.sh <pkg>` now performs the install closure: unpack → prewarm frontend cache → if `manifest.dsl_builder_module` is set and `site/dist/index.html` is missing, run `npm run build` in Docker. Do not ship a Static Preview package whose installed copy lacks `site/dist/index.html`.

## Step 3.5: Local Python smoke (no platform repo needed)

Before the full runtime smoke, exercise the deterministic Python offline — this
needs **only the shipped testkit**, not a checked-out platform runtime, so it's
the verification step external developers can always run:

```bash
python3 <package>/testkit/fda_testkit.py activities/<id>
```

It stubs `app.card_system` / `app.errors`, runs `make_tools(ctx)` and
`dsl_builder.build()` against a seeded temp instance (every data-store write
schema-validated), and flags strict-mode-illegal tool schemas. A `KeyError` in
`build()` or a schema-rejecting `data_set` surfaces here in seconds. See
[`../testkit/README.md`](../testkit/README.md). The runtime SSE smoke below adds
the LLM / sandbox / card-render coverage the testkit can't.

## Step 4: End-to-end SSE smoke

Verifier 0 errors + a clean testkit smoke prove structure and deterministic
Python. **The runtime smoke proves the LLM-driven turn renders.** Run it when
you have the platform runtime (local uvicorn or a shared dev runtime); external
developers without it ship on verifier + testkit + a maintainer's runtime smoke.

Prerequisites:

1. Step 3 above produced "✓ Runtime ready"
2. Backend running: `uvicorn app.main:app --port 8000` from repo root (platform repo)

> **Working against a SHARED dev runtime instead of a local uvicorn?** If you
> have a baked `fda-dev` CLI (it ships with the dev-client bundle), skip the
> uvicorn + curl below. First run the read-only preflight
> `fda-dev --folder activities/<id> doctor`, then drive the smoke with
> `fda-dev --folder activities/<id> message --sync-first --new --smoke --pull-logs-on-error "<typical input>"`.
> The command syncs the edit, runs a fresh turn, asserts the same non-fallback
> `card_item` / `turn_completed` / `done` evidence, and downloads diagnostics
> on failure. If `doctor` reports `activityHasPriorSync=false`, stop and ask the
> user to complete the first upload in FDA Dev Client; the Coding Agent must not
> create that first server sync. Use `--events` only when raw NDJSON is needed. See
> [`../references/dev-agent-cli.md`](../references/dev-agent-cli.md).

```bash
# Instances are created implicitly on first turn — pick any kebab-case id.
IID="smoke-$(date +%s)"

# Send a turn, watch the SSE stream.
curl -N -sS --max-time 120 -X POST \
  "http://127.0.0.1:8000/v1/activity-types/<your-id>/activities/$IID/turns/stream" \
  -H 'Content-Type: application/json' \
  -d '{"text":"<typical first user input>"}' | tee /tmp/fda-stream.log

# Static Preview: probe the built SPA + DSL API.
curl -sS "http://127.0.0.1:8000/preview/<your-id>/$IID/" >/tmp/fda-preview.html
curl -sS "http://127.0.0.1:8000/preview/<your-id>/$IID/api/dsl.json" >/tmp/fda-dsl.json
```

Expected SSE event sequence (each is a `event: <name>\ndata: {...}` pair):

1. `run_started` — turn accepted
2. `agent_started` — DeepAgents loop entered
3. `agent_progress` — periodic heartbeat
4. **`card_item`** — at least one card emitted (the proof of life)
5. `state_committed` — state.json updated
6. `turn_completed` — assembled turn output has been committed
7. `done` — payload includes `llm_bill` totals

Static Preview also: `/preview/<activity_type_id>/<instance_id>/` returns HTML and `/api/dsl.json` returns JSON. If `/preview/.../` returns `{"error":"site not built"}`, rerun the build/install step and confirm `site/dist/index.html` exists.

## Step 5: Evidence-first gate

Before the Ship Verification block: every "ready" / "完成" claim must sit immediately after the actual verifier exit code + the actual SSE event list — paste output, then conclude. No evidence → state what's missing instead of claiming done. (This governs the human-written summary, not the tool calls themselves.)

## Step 6: Write the Ship Verification block

```markdown
## Ship Verification

- **Semantic review**: CONFLICT 0; accepted SMELL/NOTE: <list + reason, or "none">
- **Builder bundle**: <absolute package path> · version <plugin.json version>; no mixed checkout/cache assets
- **Verifier**: 0 errors. Output:
  ```
  <paste full stdout, including warnings>
  ```
- **Testkit smoke**: `python3 <package>/testkit/fda_testkit.py activities/<id>` → <paste result line>
- **Runtime setup/build**: `bash <package>/tools/setup-runtime.sh <id>` and, for Static Preview, `npm run build` or `bash <package>/tools/install-activity.sh <pkg>` → `site/dist/index.html` exists
- **E2E smoke**: <method> <url> → <status>; events: <list>; output_card "<title>" emitted. *(Platform-runtime step — if you don't have the runtime, record "deferred to maintainer runtime smoke" and the maintainer pastes it.)*
- **Suggested smoke inputs** *(optional)*: <随包指定的必测输入，如 "大纲 turn 同 turn 出封面" 这类历史事故线>；maintainer 跑 E2E 时照此复现。
- **Warnings acknowledged**: <reason for accepting / planned remediation>
- **Files changed**: <git diff --stat output>

Activity <id> is ready to ship.
```

No Ship Verification block = no completion claim. The **semantic review,
verifier, and testkit smoke lines are always required**; the runtime E2E line
is required when you have the runtime, otherwise it is explicitly deferred to
a maintainer. Maintainer runtime smoke / fda-logs may be repeated after handoff;
`fda-dev` reuses the authenticated FDA Dev Client session when available.

## Done

Once the Ship Verification block exists, the activity is shippable. The user can `git add`, commit, and merge.

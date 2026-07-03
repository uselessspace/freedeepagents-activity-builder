# Workflow 06: Verify and ship (MANDATORY)

This is the **terminal gate**. The activity is shippable only after a `## Ship Verification` block exists with pasted verifier + smoke output (see step 6).

## Step 1: Run the verifier

```bash
python <package>/tools/activity_verifier.py
```

Or, to see only your activity's output:

```bash
python <package>/tools/activity_verifier.py 2>&1 | grep activities/<your-id>
```

Parse the output:
- Lines starting `ERROR ` → BLOCK ship
- Lines starting `WARNING ` → don't block but must be acknowledged in the Ship Verification block

Exit code: `0` if no errors, `1` if any errors.

## Step 2: Fix one thing at a time

See [../policies/fix-loop.md](../policies/fix-loop.md). Do **not** batch fixes — verifier errors interact and you'll lose track of which change caused what.

| Common ERROR | Cause | Fix |
|---|---|---|
| `manifest.json: disallowed field: foo` | non-whitelist field | delete the field, or move the value into `data.schema.json` if it's business state |
| `card_templates ... missing vars` | `*.json` without sibling `*.vars.json` | add the vars file (or delete orphan template) |
| `frontend-src private state read` | `frontend-src/` reads `instance.data.*` | move to OutputArtifact / cards |
| `generic runtime hardcoded activity` | `app/`/`schemas/` references the activity id | move logic into `activities/<id>/skills/` |
| `skills= self._skill_sources` | `app/runner.py` stopped using DeepAgents native loading | restore `skills=self._skill_sources(manifest)` |
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
python <package>/testkit/fda_testkit.py activities/<id>
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
> uvicorn + curl below and drive the smoke in one command:
> `fda-dev --folder activities/<id> message --sync-first --new --events "<typical input>"`
> — it syncs your edit, runs the turn, and streams the same `card_item` /
> `turn_completed` / `done` events. See [`../references/dev-agent-cli.md`](../references/dev-agent-cli.md).

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

Static Preview also: `/preview/<activity_type_id>/<activity_id>/` returns HTML and `/api/dsl.json` returns JSON. If `/preview/.../` returns `{"error":"site not built"}`, rerun the build/install step and confirm `site/dist/index.html` exists.

## Step 5: Evidence-first gate

Before the Ship Verification block: every "ready" / "完成" claim must sit immediately after the actual verifier exit code + the actual SSE event list — paste output, then conclude. No evidence → state what's missing instead of claiming done. (This governs the human-written summary, not the tool calls themselves.)

## Step 6: Write the Ship Verification block

```markdown
## Ship Verification

- **Verifier**: 0 errors. Output:
  ```
  <paste full stdout, including warnings>
  ```
- **Testkit smoke**: `python <package>/testkit/fda_testkit.py activities/<id>` → <paste result line>
- **Runtime setup/build**: `bash <package>/tools/setup-runtime.sh <id>` and, for Static Preview, `npm run build` or `bash <package>/tools/install-activity.sh <pkg>` → `site/dist/index.html` exists
- **E2E smoke**: <method> <url> → <status>; events: <list>; output_card "<title>" emitted. *(Platform-runtime step — if you don't have the runtime, record "deferred to maintainer runtime smoke" and the maintainer pastes it.)*
- **Suggested smoke inputs** *(optional)*: <随包指定的必测输入，如 "大纲 turn 同 turn 出封面" 这类历史事故线>；maintainer 跑 E2E 时照此复现。
- **Warnings acknowledged**: <reason for accepting / planned remediation>
- **Files changed**: <git diff --stat output>

Activity <id> is ready to ship.
```

No Ship Verification block = no completion claim. The **verifier + testkit smoke lines are always required** (both run with no platform repo); the runtime E2E line is required when you have the runtime, otherwise it's deferred to a maintainer and noted as such — never silently dropped. maintainer 的 runtime smoke / fda-logs 回传可按需重复——交接不是一次性的；若开发者已拿到 `fda-dev` token，用共享 dev runtime 自己复跑即是等价替代（见 [../references/dev-agent-cli.md](../references/dev-agent-cli.md)）。

## Done

Once the Ship Verification block exists, the activity is shippable. The user can `git add`, commit, and merge.

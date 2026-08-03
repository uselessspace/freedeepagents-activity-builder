# `fda-dev` — Coding Agent CLI for a live dev runtime

`fda-dev` is the narrow, auditable development interface for a **running**
FreeDeepAgents dev runtime. It lets a Coding Agent verify connectivity, compare
local and server state, sync source, run a real turn, enforce smoke evidence,
pull server source, and download diagnostics without exposing a generic raw API
client.

This reference owns the command, side-effect, authentication, and output rules
for `/activity-dev-cli`. `/activity-smoke`, `/activity-diagnostician`, and
`/activity-packager` route here when they need a shared runtime.

## Availability and identity

The FDA Dev Client release ships the CLI with the server URL baked in:

- Windows ZIP: `fda-dev.exe` beside the GUI executable.
- macOS: `fda-dev-macOS-arm64` beside the DMG; place it on `PATH` as
  `fda-dev` or invoke its absolute path.

Discover it before use:

```bash
command -v fda-dev
# PowerShell: Get-Command fda-dev.exe
```

If it is unavailable, do not invent a binary path. Continue with the bundled
verifier and offline testkit; record the live-runtime smoke as deferred.

The CLI and GUI are two interfaces to one native client session. The normal
path is: log in once through FDA Dev Client, then let the CLI reuse the same
atomic credential group. The release URL can be overridden when needed
(precedence: flag > environment > baked value):

```bash
export FDA_GO_SERVER=https://Intelliland.cn:18084
fda-dev --folder activities/<id> doctor
```

`--folder` points to the activity being developed. Its basename is the default
`activity_type_id`; use `--activity <id>` only when they intentionally differ.

## Agent decision table

| Goal | Start with | Side effect |
|---|---|---|
| Verify URL, OpenAPI, TLS, login, and activity recognition | `doctor` | none |
| List authenticated activities | `ping` | none |
| Compare local digest with server version / seq / digest | `status` | none |
| Preview an upload | `sync --dry-run` | none |
| Push local source to the development server after its first GUI upload | `sync` | modifies dev server |
| Run one real turn | `message "<text>"` | creates/updates a dev instance |
| Sync, run, smoke-gate, and collect failure logs | `message --sync-first --new --smoke --pull-logs-on-error "<text>"` | modifies dev server and creates a turn |
| Download recent traces | `logs [--instances N] [--turns N]` | writes local `fda-logs/` only |
| Preview adopting server source | `pull --dry-run` | none |
| Adopt server source after confirmed divergence | `pull --force` | overwrite-merges local source |
| Inspect supported commands and boundaries | `capabilities` | none |

Start with read-only inspection. `doctor` being healthy does not require the
activity to have uploaded source. If `activityHasPriorSync=false` or `status`
reports `not-synced`, stop: explain that the user must open FDA Dev Client and
complete the activity's first upload. A Coding Agent cannot perform or bypass
that first upload.

## Recommended development loop

Use the shortest safe loop that proves the current hypothesis:

```bash
# 1. Read-only preflight.
fda-dev --folder activities/<id> doctor
fda-dev --folder activities/<id> status

# STOP here when activityHasPriorSync=false. Ask the user to perform the first
# upload in FDA Dev Client, then rerun doctor/status.

# 2. Inspect the upload boundary before the first write.
fda-dev --folder activities/<id> sync --dry-run

# 3. Push, run a fresh turn, enforce smoke evidence, and fetch logs on failure.
fda-dev --folder activities/<id> message \
  --sync-first --new --smoke --pull-logs-on-error \
  "<a representative user message>"
```

`--smoke` applies `/activity-smoke`'s standard: at least one real,
non-fallback `card_item`, plus `turn_completed` and `done`. It writes the
verdict to stderr and exits non-zero on failure. On failure,
`--pull-logs-on-error` downloads the diagnostic snapshot into
`<folder>/fda-logs/`; route its `turn_id` and trace evidence to
`/activity-diagnostician`.

Use `--events` only when trace-level SSE evidence is needed. It emits NDJSON,
one event per stdout line:

```bash
fda-dev --folder activities/<id> message \
  --sync-first --new --smoke --events \
  "<a representative user message>" > /tmp/fda-turn.ndjson
```

## Command and output contract

| Command | Result |
|---|---|
| `doctor` | Separates URL/OpenAPI, credentials, authenticated ping, manifest, and activity-state checks. |
| `ping` | Validates the authenticated Developer API and lists visible activities. |
| `status` | Reports states such as `clean`, `local-changes`, `not-synced`, or `no-local-folder`. |
| `sync [--dry-run] [--build] [--version X.Y.Z]` | Packs local activity source; optionally builds Static Preview; previews it, or updates an activity that already has a GUI-created server sync. |
| `message <text> [flags]` | Runs one real turn only after the activity has a completed server sync; returns the distilled result or raw SSE events. |
| `logs [--instances N] [--turns N]` | Replaces the local diagnostics snapshot under `fda-logs/`. |
| `pull --dry-run` | Compares local and server state without writing. |
| `pull --force` | Downloads and overwrite-merges server source after explicit divergence acknowledgement. |
| `capabilities` | Returns the machine-readable command and security catalog. |

JSON is the default. Success goes to stdout:

```json
{"ok":true,"command":"status","data":{"state":"local-changes"}}
```

Errors go to stderr with a non-zero exit code:

```json
{"ok":false,"command":"doctor","error":{"type":"auth","code":"DEVELOPER_SESSION_REPLACED","message":"...","hint":"..."}}
```

Agents decide success from the process exit code or the top-level `ok`, never
from human prose. Use `--format text` only for an operator-facing view.
`message --json` remains a legacy alias for the default distilled JSON result;
`--events` changes stdout to NDJSON. Auxiliary notices stay on stderr.

### Important `message` flags

| Flag | Effect |
|---|---|
| `--sync-first` | Sync local source before the turn; this is a server write. |
| `--new` | Use a fresh throwaway instance instead of perturbing a stable human session. |
| `--smoke` | Enforce real `card_item` + `turn_completed` + `done`; fail the process otherwise. |
| `--pull-logs-on-error` | Download diagnostics when the turn or smoke assertion fails. |
| `--events` | Stream raw SSE events as NDJSON. |
| `--timeout <seconds>` | Bound the whole request; `0` means no client-side limit. |
| `--file <path>` | Attach a file under `--folder`. External files require explicit opt-in. |

## Authentication behavior

Shared native credentials live in `~/.fda-dev/gui-session.json`, guarded by
`~/.fda-dev/gui-session.lock`. Access token, RefreshToken, and ID token rotate
and persist as one atomic group. An ordinary 401 triggers one serialized
refresh and one retry; terminal session errors clear only the rejected
credential so a newer GUI login is not accidentally erased.

If `doctor` reports a terminal code such as `DEVELOPER_SESSION_REPLACED`,
`DEVELOPER_SESSION_REVOKED`, or `DEVELOPER_REFRESH_EXPIRED`, present that code
and hint to the user. Do not describe every auth failure as “offline” and do
not retry in a loop.

## Mandatory safety rules for Coding Agents

- Never print access tokens, RefreshTokens, ID tokens, or passwords.
- Never call `login --replace-session` autonomously. It replaces the current
  native client session and may log out another client.
- Do not use `--token` unless the user explicitly supplied a CI/break-glass
  token; a static token cannot refresh itself.
- Do not use `--allow-outside-file` without explicit authorization for the
  exact attachment path.
- Do not run `pull --force` without explicit authorization to overwrite-merge
  the target local activity after reviewing `pull --dry-run`.
- Before the first actual `sync`, run `doctor`, `status`, and
  `sync --dry-run`, and verify the intended activity id/folder.
- If `activityHasPriorSync=false`, `relation=not-synced`, or the CLI returns
  `INITIAL_UPLOAD_REQUIRES_DESKTOP_CLIENT`, stop and guide the user to complete
  the first upload in FDA Dev Client. Never attempt to bypass the gate.
- Treat `sync`, `message --sync-first`, and `message` as dev-server mutations.
  They are valid when the user asked to develop/test that activity, but still
  report what was changed.
- Keep loops bounded. The CLI enforces persistent, cross-process limits of
  **12 server-facing invocations/minute and 120/hour per server origin**; the
  server remains a second line of defense, and only one `message` may be in
  flight per activity. On `CLIENT_RATE_LIMITED`, stop and wait the returned
  `retryAfterSeconds`. Never evade it with parallel processes, a different
  working folder, or rapid retries.
- Never commit `fda-logs/`, `.fda/`, or native credential files.

## Boundary

`fda-dev` only calls allowlisted Go Developer API operations. There is no raw
endpoint passthrough. Local packing excludes secrets and build noise through
the shared sync-core policy; outside-folder attachments and divergent pulls
require explicit opt-in. Client interactions are summarized in
`~/.fda-dev/interactions.jsonl`, and server-side calls remain audited.

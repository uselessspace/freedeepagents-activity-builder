# fda-dev — the Coding Agent CLI for a live dev runtime

`fda-dev` lets a Coding Agent drive a **running** FreeDeepAgents dev runtime from
the terminal: push the activity it just edited, run a real turn against it, read
the full event stream, and pull diagnostics — the one-stop edit→test loop. It is
the headless twin of the GUI dev client (both wrap the same `sync-core`); the
only thing it adds is `message` (sending a turn + reading its SSE), which the GUI
never did.

## Contents

- Getting the binary · Commands
- The one-stop loop · `--smoke` · Limits & audit · Boundary

Use it whenever a dev runtime is reachable and you want to confirm an activity
*actually serves a turn* — it automates exactly the "start service + drive a
turn" step that `/activity-smoke` otherwise leaves manual.

## Getting the binary

The colleague's dev-client bundle ships a pre-configured `fda-dev` with the
server URL baked in (built via `clients/dev-client/build-cli.sh` /
`build-all.sh`). After `fda-dev login`, the agent can run it with no `--server`:

```bash
fda-dev --folder <activity-folder> ping
```

If not baked, pass config explicitly or via env (precedence: flag > env > baked):

```bash
export FDA_DEV_SERVER=http://192.168.1.225:8000 FDA_GO_ACCESS_TOKEN=<go-access-token>
fda-dev --folder activities/<id> ping
```

`--folder` points at the activity you're working on (its basename is the default
`activity_type_id`; override with `--activity <id>`).

## Commands

| Command | What it does | Endpoint |
|---|---|---|
| `ping` | Validate server + token; list activities. | `/dev/ping` |
| `status` | This activity's version / seq / digest on the server. | `/dev/ping` |
| `sync [--build] [--version X.Y.Z]` | Push the folder (code hot-reloads next turn; `--build` also runs the frontend build). | `/dev/sync` |
| `message <text> [flags]` | Run ONE real turn against the activity and stream its result. | `/dev/agent/message/stream` |
| `logs [--instances N] [--turns N]` | Pull recent `trace.jsonl` diagnostics into `<folder>/fda-logs/`. | `/dev/logs` |
| `pull` | Overwrite-merge the server's current source into the folder. | `/dev/pull` |

### `message` flags

| Flag | Effect |
|---|---|
| `--events` | Stream EVERY SSE event verbatim as NDJSON to stdout — the full turn (`run_started`/`turn_started`/`agent_progress`/`card_item`/`state_committed`/`turn_completed`/`done`/`error`). **This is what you parse for smoke evidence.** |
| `--json` | Print one distilled result object (`{ok, output, error, turn_id, instance_id, events_count}`). |
| `--sync-first` | `sync` the folder (code only, no build) BEFORE the turn — edit→test in one command. |
| `--pull-logs-on-error` | On a failed turn, auto-pull the trace into `fda-logs/`. |
| `--smoke` | Assert the `/activity-smoke` evidence (real `card_item` + `turn_completed` + `done`); print `SMOKE: PASS/FAIL` to stderr and **exit non-zero on FAIL**. No parser needed. |
| `--timeout <secs>` | Whole-request timeout; `0` (default) = no limit. Set it to bound a possibly-stuck turn (keep it high — the server already bounds the LLM). |
| `--new` | Use a fresh throwaway instance (so you don't perturb a human's live session). Default instance is stable: `dev-cli-<uid>-<user>`. |
| `--file <path>` | Attach a file (must live under `--folder` unless `--allow-outside-file`). |

Auxiliary lines (the `synced …` line, pull-logs notices) go to **stderr**, so
`--events`/`--json` stdout stays clean and machine-parseable.

## The one-stop loop

After editing an activity's `tools.py` / cards / prompt, verify it serves a turn
in a single command:

```bash
fda-dev --folder activities/<id> message --sync-first --new --events "<a representative user message>" \
  > /tmp/turn.ndjson 2> /tmp/turn.err
```

`--sync-first` pushes your edit; the turn runs against it; `--events` gives you
the whole stream to assert on. (`stderr` carries the `synced v… seq=… files=…`
confirmation.)

## Smoke in one command: `--smoke`

`/activity-smoke` passes a turn when it emitted a real (non-fallback) `card_item`
+ `turn_completed` + `done`. The CLI builds that assertion in — no parser needed.
`--smoke` prints the verdict to **stderr** and **exits non-zero on FAIL**, so an
agent gates on the exit code directly:

```bash
fda-dev --folder activities/<id> message --sync-first --new --smoke "<a representative user message>"
# stderr → SMOKE: PASS (card_item=1 turn_completed=1 done=1)   [exit 0]
#       or SMOKE: FAIL (card_item=0 ...)                       [exit 1]
```

It already applies the fallback rule (a runtime zero-emit fallback card does NOT
count). Compose with `--events`/`--json` to also capture the stream. On FAIL,
add `--pull-logs-on-error` to drop the trace into `fda-logs/`, then route the
`turn_id` to `/activity-diagnostician`.

## Limits & audit (don't hammer)

The server caps Coding-Agent traffic at **100 interactions/min per token** (every
`message`/`sync`/`logs`/`pull`/`status` counts) plus **1 in-flight `message` per
activity**. The client fast-fails first; the server is the binding limit. Every
call is recorded both client-side (`~/.fda-dev/interactions.jsonl`) and
server-side (`runtime/dev-agent-interactions.jsonl`). Keep test loops tight — a
typical `--sync-first` iteration is 2 interactions (sync + message).

## Boundary

`fda-dev` only talks to the token-gated `/dev/*` routes (mounted only when
`DEV_SYNC_ENABLED`); it never touches the public `/v1` API. `fda-logs/` and
`.fda/` are gitignored — never commit them.

# Reference — `read_document` capability

Opt-in via `manifest.capabilities: ["read_document"]`. Gives the agent one tool:

## `read_document(source_file_id | source_path | source_url | source_artifact_id)`

Converts an uploaded document to Markdown the agent can read. Supply **exactly one** source.

| Source param | Use when |
|---|---|
| `source_file_id` | The user uploaded a file THIS turn (e.g. `file_0`). Most common. |
| `source_path` | A document already under `/instance/...` (e.g. a build output). |
| `source_url` | A public http(s) URL — **subject to `DOC_INGEST_URL_ALLOWLIST`** (default deny). |
| `source_artifact_id` | A document artifact committed in an earlier turn. |

**Supported formats:** PDF, Word (`.docx`), PowerPoint (`.pptx`), Excel (`.xlsx`), HTML, CSV, JSON.

**Returns (success):**
```json
{ "markdown": "...", "char_count": 12345, "truncated": false, "source_kind": "file", "title": "..." }
```
When `truncated` is `true`, the full Markdown is persisted as a `text/markdown`
artifact and the result includes a `sandbox_path` (e.g.
`/instance/artifacts/<turn_id>/<artifact_id>.md`). The agent recovers the rest by
reading that path with `read_file` (paginating via `offset`/`limit` as needed) —
NOT by calling `read_document` again on the `.md` (that would just re-truncate).

**Returns (failure):** `{ "error": "..." }` — do NOT retry the same source; the
format is unsupported or the file is unreadable.

**Runtime caps:** these are runtime/operator environment variables (NOT activity
manifest/runtime.json fields), namely `DOC_INGEST_MAX_SOURCE_BYTES` (20 MiB),
`DOC_INGEST_MAX_OUTPUT_CHARS` (50000), `DOC_INGEST_MAX_PER_TURN` (10),
`DOC_INGEST_URL_ALLOWLIST` (comma-separated hosts), and
`DOC_INGEST_TIMEOUT_SECONDS` (60).

**Boundaries:** conversion runs host-side (not in the sandbox); the agent never
builds the Markdown itself. Use `read_document` to *ingest* a document, then
emit cards / artifacts as usual.

**Conversion timeout:** when `DOC_INGEST_TIMEOUT_SECONDS` > 0 (default 60), each
conversion runs in a killable subprocess and is terminated past the deadline,
returning `{"error": "...timed out..."}` so a pathological file can't peg the
worker. Set it to `0` to run in-process (no subprocess overhead, no timeout
protection — then `DOC_INGEST_MAX_SOURCE_BYTES` is the only bound).

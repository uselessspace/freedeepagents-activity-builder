# Reference — Error Classes

Lookup: trace signature → root cause → fix location → validation step. Each
row is a real, observed failure mode. When you add a new row, include a real
trace excerpt under "Signature" so future diagnoses can string-match.

> Path conventions: `policies/` and `references/` paths below are relative to
> the `freedeepagents-activity-builder` package root, **not** to this file.

---

## E1 — DeepSeek strict-mode tool-param schema rejection

**Signature (in `trace.jsonl`):**

```
"llm_error" ... "BadRequestError(\"Error code: 400 - {'error': {'message':
  'Invalid tool parameters schema : field `anyOf`: one of `type`, `anyOf`,
  `$ref` field is required'"
```

**Root cause:** an activity `@tool` in `activities/<id>/tools.py` uses a bare
`list` / `dict` annotation, or a Union (other than `str | None`). Pydantic
turns these into `{"type":"array","items":{}}` or `{"anyOf":[{...},{}]}`;
DeepSeek strict mode rejects the empty branch.

**User-visible symptom:** turn fails immediately on first LLM call; no card
ever emits; UI shows generic "AI 本轮未能给出有效回答".

**Fix location:**
- `activities/<id>/tools.py` — narrow the offending param to `str = "[]"`
  and parse JSON inside the function. Reference implementations:
  `activities/bedtime-story/tools.py::_parse_snippets`.
- Authoritative policy: `policies/llm-output-discipline.md §8d`.

**Validation:** run `activity-verify` (it includes the strict-tool-schema
self-check); every tool should print `ok`.

---

## E2 — Tool-call JSON parse failure (unescaped quotes / backslashes)

**Signature:**

```
"chain_error" ... "Function card_emit arguments are not valid JSON.
  JSONDecodeError: Expecting ',' delimiter ..."
```

Or `invalid_tool_call` events in `trace.jsonl` followed by retries with no
emit.

**Root cause:** `card_emit` / `card_emit_template` was called with a card
whose markdown `content` contains raw ASCII double-quote characters
(`"`), unescaped backslashes (`\path\to\file`), or literal newlines —
LLM serialization produces JSON that breaks at the embedded boundary.

**User-visible symptom:** retry storm in trace (multiple `execute` / `read_file`
attempts), then the runtime's `zero-emit-fallback` card displays after ~19s.

**Fix location:**
- Wherever the agent constructs the card content — usually a host SKILL.md
  template snippet or a card_template `.json` with literal placeholders.
- Authoritative policy: `policies/llm-output-discipline.md §8b`.

**Validation:** re-run the turn (`activity-smoke`) with a similar input;
check `trace.jsonl` has no `invalid_tool_call` events.

---

## E3 — OutputValidationError on a card block

**Signature:**

```
"OutputValidationError" ... "Extra inputs are not permitted"
```

Or a tool result like:

```
{"error":"...","hint":"use 'images: [{read_url, title, description}]'..."}
```

**Root cause:** a block field name is off the StrictModel whitelist
(`src` / `alt` / `caption` instead of `images[].read_url` / `description`;
`file_url` on artifact instead of `url`; FormField `input_type=radio`).

**User-visible symptom:** card never reaches the user; turn fails with the
runtime's pydantic error.

**Fix location:**
- Either `activities/<id>/card_templates/<name>.json` (template field name)
  or the agent's `card_emit` call shape.
- Field tables: `references/card-block-types.md`.
- Authoritative policy: `policies/llm-output-discipline.md §4` (artifact),
  §8 (StrictModel field tables).

**Validation:** `activity-verify` runs the package verifier which has
WRONG_BLOCK_FIELDS / WRONG_ARTIFACT_FIELDS detection (see
`tools/activity_verifier.py`).

---

## E4 — Template id not in available templates

**Signature:**

```
"chain_start" ... card_emit_template ... template_id="<x>"
"llm_error" or tool result: {"error":"template <x> not found",
  "available_templates":[...]}
```

**Root cause:** the host SKILL routed to a template name that does not exist
in `activities/<id>/card_templates/`. Common causes: typo, missing paired
`.vars.json` file, or a renamed template that SKILL.md still references by
the old name.

**User-visible symptom:** turn fails before emit; tool result lists every
template that does exist.

**Fix location:**
- Add the missing `<x>.json` + `<x>.vars.json` files, OR change the SKILL.md
  to call an existing template.
- Authoritative reference: `references/card-system-tools.md` §1 (error returns).

**Validation:** `activity-verify` will flag any orphan `.json` without
`.vars.json`; otherwise re-run the turn.

---

## E5 — Zero-emit fallback (agent didn't call any emit tool)

**Signature (in `trace.jsonl`):**

```
"system_message_injected" ... "你必须 emit 卡片..."
"card_item" ... template="runtime.zero_emit_fallback"
```

Or a turn where the only card is the runtime fallback.

**Root cause:** agent returned without calling `card_emit*` / `artifact_emit`
/ `mark_status`. Common causes: agent wrote a final-JSON answer in content
(which is discarded), agent read SKILL.md repeatedly without ever calling a
tool, or agent looped on `execute` / `read_file`.

**User-visible symptom:** user sees the generic "AI 本轮未能给出有效回答" card.

**Fix location:**
- The activity's host SKILL.md fast-path section — make the single emit
  explicit and HARD ("emit one card then stop").
- Authoritative policy: `policies/llm-output-discipline.md §8c`
  (single-emit-then-stop).

**Validation:** `activity-smoke` on a greeting input; trace should show one
non-fallback `card_item` and stop.

---

## E6 — `image_edit` source staging requires object storage

**Signature:**

```
{"error":"image_edit requires object storage for source staging ..."}
```

**Root cause:** the activity declared `capabilities: ["image_edit"]` but the
deployment has no object storage configured; wanxiang takes URLs,
not bytes (the runtime stages the source bytes to the object store first).

**User-visible symptom:** any image_edit call returns an error card; the
generate path may still work if `IMAGE_GEN_DEFAULT_STORE=sandbox` is set.

**Fix location:**
- Deployment side: configure object storage — `OBJECT_STORAGE_PROVIDER`
  (`minio`/`s3`) + the matching `MINIO_*` env in repo `.env`.
- OR activity side: drop `image_edit` from `manifest.capabilities` and only
  use `image_generate`.
- Authoritative reference: `references/image-tools.md` § `image_edit` 重要约束.

**Validation:** retry the same turn after configuring minio, or after
reinstalling the activity with the trimmed capability list.

---

## E7 — External dependency unavailable (Tavily / docker timeout / API key)

**Signature:**

```
"tool_error" ... TAVILY_API_KEY missing
"tool_error" ... docker timeout
"tool_error" ... <provider> API key
```

**Root cause:** the activity called an external service but its credentials
or network are unavailable.

**User-visible symptom:** depends on the activity's graceful-degrade policy.
A well-written activity emits a degraded error card and continues; a poorly
written one surfaces the raw tool error.

**Fix location:**
- Activity side: add a graceful-degrade workflow that catches the tool error
  and emits a user-facing error card. Reference:
  `activities/bedtime-story/skills/bedtime-story-host/policies/graceful-degrade.md`.
- Deployment side: provision the missing key / network.
- Authoritative policy: each activity's own `graceful-degrade.md` —
  whatever degrade behavior fits the activity's design (error card,
  fallback content, skip-the-step) as long as the turn still completes.

**Validation:** simulate the failure (unset env var) and confirm the activity
emits its error card rather than the runtime fallback.

### E7a — TLS verify failure inside the sandbox (subtype)

**Signature (in the execute tool's stdout/stderr):**

```
[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed:
unable to get local issuer certificate (_ssl.c:992)
```

Common when a script calls `urllib.request.urlopen` over HTTPS inside the
`freedeepagents-sandbox-node:latest` docker image — Python validates
TLS by default but the sandbox image does not ship a populated
`ca-certificates` store, so verification fails for every HTTPS request.

**User-visible symptom:** the activity's `save_search_session` (or
equivalent) records `error="[SSL: CERTIFICATE_VERIFY_FAILED] ..."` with
zero results across every platform; the agent gracefully degrades to a
LLM-only report. The turn still completes but the report's market
references are estimates rather than real data.

**Fix location (activity-side, fastest):**

- Patch the script with a verified-first / unverified-fallback opener.
  Reference implementation:
  `activities/bedtime-story/skills/tavily-search/scripts/tavily_search.py::_open_with_ssl_fallback`.
  Tavily responses are non-sensitive search snippets, so the fallback
  is a safe trade-off; verified context is always tried first so a
  properly-provisioned sandbox or the host machine still gets full
  TLS verification.

**Fix location (deployment-side, treats the root cause):**

- Edit `Dockerfile.sandbox` to `apt-get install -y ca-certificates &&
  update-ca-certificates`, then rebuild the image via
  `bash <package>/tools/setup-runtime.sh --force`. Every sandbox script
  benefits after this — including future activities.

**Validation:**

- Re-run the same turn (activity-side fix): `save_search_session.error`
  should be empty and `references` should be non-empty.
- Or unset `TAVILY_API_KEY` to force a different E7 path and confirm
  the activity's graceful-degrade card still appears.

---

## E8 — Manifest / runtime field not on the verifier whitelist

**Signature (verifier output, not trace):**

```
ERROR activities/<id>/manifest.json: manifest.json has disallowed field: <x>
ERROR activities/<id>/runtime.json: runtime.json has disallowed field: <x>
```

**Root cause:** the activity added a field that's not in
`tools/activity_verifier.py::ALLOWED_MANIFEST_FIELDS` or
`ALLOWED_RUNTIME_FIELDS`. Common historical cause: `use_card_system` (no
longer exists). Common new-activity cause: trying to add `tags` / `version`
/ `default_*` to manifest.

**User-visible symptom:** verifier blocks ship; the runtime refuses to load
the activity.

**Fix location:**
- Move the data to its proper home (per
  `references/manifest-fields.md` § NOT allowed):
  per-instance settings → `data.schema.json`; activity behavior flags →
  host SKILL.md or its policies/; tool implementations → `tools.py`.
- Authoritative reference: `policies/manifest-allowed-fields.md`.

**Validation:** `activity-verify` exits 0 ERROR.

---

## E9 — `data.schema.json` missing top-level `default`

**Signature (verifier output or runtime behavior):**

- Verifier issues a warning about missing default, OR
- First-turn behavior: `data_get` returns `null` for declared keys; auto-inject
  block in system prompt shows `null` values; agent loops trying to
  "bootstrap" empty fields.

**Root cause:** `activities/<id>/data.schema.json` has `properties` declared
but no top-level `"default": {...}` object. Runtime seeds new instances from
that default; without it, every key starts as `null`.

**User-visible symptom:** first turn behavior weird — agent acts like the
typed-KV doesn't exist, sometimes loops calling `data_get`.

**Fix location:**
- Add a top-level `"default": { ... }` to `data.schema.json` with an entry
  for each declared property (matching the property's type — `[]` for
  arrays, `{}` for objects, `""` for required strings, etc.).
- Authoritative reference: `references/data-store-tools.md` § 常见踩坑 #1
  + § 启用步骤 #4.

**Validation:** delete the test instance dir, create a new one, and check
the auto-inject block in the system prompt shows the default shape.

---

## E10 — Static Preview module / callable missing, or `/preview` 404

**Signature (verifier output or runtime):**

```
ERROR activities/<id>: tools_module 'tools' declared but tools.py missing
ERROR activities/<id>: dsl_builder_module 'dsl_builder' missing build() callable
```

Or runtime: `GET /preview/<activity_type_id>/<activity_id>/` returns 404, `/api/dsl.json` returns
500.

**Root cause:** manifest declares `tools_module: "tools"` or
`dsl_builder_module: "dsl_builder"` but the corresponding file does not
exist, OR it exists but lacks the required callable (`make_tools(ctx)` for
tools_module; `build(instance_dir) -> dict` for dsl_builder_module).

**User-visible symptom:** activity loads but the SPA never renders / shows a
blank page.

**Fix location:**
- Either add the missing `activities/<id>/tools.py` (export `make_tools(ctx)`)
  / `activities/<id>/dsl_builder.py` (export `build(instance_dir)`),
- OR remove the manifest field if the activity is actually card-only.
- Authoritative reference: `references/manifest-fields.md` § tools_module
  + § dsl_builder_module; `references/verifier-checks.md` Hard checks.

**Validation:** `activity-verify`; for Static Preview, also probe
`/preview/<activity_type_id>/<activity_id>/api/dsl.json` returns a JSON object (not 404 / 500).

---

## E11 — image_generate produces a pretty but textless image when text was requested

**User-visible symptom:** the user sees a beautifully composed image
(traditional motifs, balanced layout, often with a decorative empty
central panel) — but the requested text / greeting message that was
supposed to be rendered inside the image **is missing**. Common in
greeting-card / poster / 海报 / 标语 generation flows.

**Signature (in `image_generate`'s `tool_start` input):**

```jsonc
{
  "prompt": "... 画面中央留白区域用于放置贺卡文字 ...",        // ← passive "leave a space for text"
  "negative_prompt": "low quality, blurry, text, cartoonish ..." // ← "text" in negatives!
}
```

Either pattern alone is enough to make the model strip the text out.

**Root cause:** modern Wanxiang (DashScope wanx-v1) can render short
Chinese strings fairly reliably **but it does literally what the prompt
says**:

1. If `negative_prompt` contains `text` / `words` / `characters` / `chinese characters` / `letters` / `no text` / `typography` / `writing`, the model treats the requested text as a thing to avoid and produces a textless image.
2. If the prompt describes the text area as 「留白区域用于放置文字」 / 「适合放置祝福文字的位置」 / 「预留文字位置」 / 「文字将由用户自己填入」, the model interprets that as "render an empty placeholder for the user to fill later" and doesn't draw the text.

Both are easy traps for an LLM-driven prompt assembler because they
sound like reasonable English-style prompt hygiene ("avoid bad outputs
including text artifacts" / "leave room for the title").

**Fix location:**

- The activity's image-generation workflow / SKILL. See
  `references/image-tools.md` for the `image_generate` fast-path shape, the
  `negative_prompt` do-not-list, and 正确写法 vs 反例 guidance.
- Authoritative rule: never put `text` / `words` / `characters` /
  `letters` / `no text` / `writing` / `typography` in `negative_prompt`
  when the image is supposed to contain text.
- Use an active sentence with the text quoted inline: 「画面中央**已经**
  用书法字体呈现"<message>"」 — not 「中央**留白**用于放置文字」.

**Validation:** re-run image_generate with the corrected prompt; the
returned image should contain the requested text. If still missing
after the prompt fix, the issue is on the provider side (rare) — open
a separate diagnosis.

---

## E12 — Undeclared third-party Python dependency

**Signature (verifier output, not trace):**

```
ERROR activities/<id>/tools.py: imports third-party package '<pkg>' but it is
not declared in activities/<id>/requirements.txt ...
```

May also surface at runtime as a `ModuleNotFoundError: No module named '<pkg>'`
on a fresh host (or in the Docker image) when the import path first runs.

**Root cause:** the activity's `tools.py` / `dsl_builder.py` / `handlers.py` (or
a helper module it ships) imports a package that is neither Python stdlib, nor
in the platform baseline (`references/runtime-python-baseline.txt`), nor a
first-party `app.*` import, nor a sibling module the activity ships — and it is
not listed in `activities/<id>/requirements.txt`. All activities share one venv;
the runtime only installs a dependency if the activity declares it
(`app/dev_sync.py` pip step + `Dockerfile`), so an undeclared import works on
the author's machine (where it happens to be installed) but `ImportError`s
elsewhere.

**User-visible symptom:** verifier blocks ship; on a fresh host the activity
fails the first time the import executes.

**Fix location:**
- Add a pinned line (`<pkg>==<version>`) to `activities/<id>/requirements.txt`.
- If the import is genuinely a *platform* dependency you added to the host's own
  `requirements.txt`, regenerate the baseline instead:
  `.venv/bin/python <package>/tools/gen-python-baseline.py`.
- Authoritative reference: `references/python-dependencies.md`.

**Validation:** `activity-verify` exits 0 ERROR; on a clean venv,
`pip install -r activities/<id>/requirements.txt` then importing the module
succeeds.

---

## How to add a new class

1. Reproduce the failure once and copy the trace signature (the most stable
   substring of the error).
2. Identify the file the fix lands in.
3. Find or write the authoritative policy / reference; cite by relative path
   + section number.
4. State the validation command and the expected output.

Append the new class with the next `E<n>` id. Don't reuse retired ids.

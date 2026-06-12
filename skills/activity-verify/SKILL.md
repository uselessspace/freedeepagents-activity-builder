---
name: activity-verify
description: >-
  独立工具·静态校验。打包前快速（under 5s、不调 LLM）跑 bundled verifier + strict-tool
  schema 自检，返回 ship-ready 或一份待修清单。活动文件改完、想先确认合法/合规时用。
  Use to statically verify an FDA activity before pack / install / smoke.
  Runs the bundled activity verifier and the strict-tool-schema self-check.
  Returns ship-ready / list of fixes; no LLM call needed.
---

# Activity Verify

> **何时用**：文件写完、打包前做静态体检。只静态查——要确认真能跑一个 turn 用 `/activity-smoke`。

Static, fast (< 5s for the whole repo). Two checks combined.

## Python runtime

The two checks have **different** requirements:

- **Check 1 (bundled verifier)** is pure static AST analysis — stdlib only,
  no platform repo, no venv. Any Python **≥ 3.10** works (`python3` on PATH
  is fine; 3.9 crashes on `sys.stdlib_module_names`).
- **Check 2 (strict-tool-schema script)** imports your `tools.py`, which
  typically does `from app.card_system import data_store` — so it needs an
  FDA repo checkout on `sys.path` and a Python with the activity-runtime
  dependencies (`langchain_core` etc.). Use **one** of:
  - `.venv/bin/python <command>` — when the repo uses the canonical
    `.venv` (this is the default for FreeDeepAgents).
  - `uv run python <command>` — when the repo is managed with uv.

  A plain `python` / `python3` on PATH almost always lacks `langchain_core`
  and will fail with `ModuleNotFoundError`.

**No platform repo?** Run the offline testkit instead of Check 2 — it stubs
`app.*`, builds `make_tools`, and checks each tool's strict-mode shape with
zero third-party deps: `python <package>/testkit/fda_testkit.py activities/<id>`
(see [../../testkit/README.md](../../testkit/README.md)).

## Check 1 — Bundled verifier

```bash
python3 <package>/tools/activity_verifier.py <repo-root>
```

Exit code:
- `0` with no `ERROR ...` lines → schema / manifest / runtime / card-template
  contracts all hold.
- `0` with `WARNING ...` lines → record them in `Ship Verification`, don't
  block.
- non-zero or any `ERROR ...` line → ship blocked; for each error, route to
  `activity-diagnostician` (most map to E8 manifest/runtime whitelist or
  E10 Static Preview module).

An `imports third-party package '<pkg>' but it is not declared in
activities/<id>/requirements.txt` error means the activity imports a package
that is neither stdlib, platform-baseline, nor declared. Fix it by adding a
pinned line to that activity's `requirements.txt` (the runtime shares one venv,
so an undeclared import `ImportError`s on a fresh host). See
[../../references/python-dependencies.md](../../references/python-dependencies.md).

## Check 2 — Strict-tool-schema self-check (activity-owned tools)

For activities with `manifest.tools_module` set, run:

```bash
.venv/bin/python <package>/skills/activity-verify/scripts/strict-tool-schema-check.py \
    --activity <activity_type_id>
```

What it does:

1. Imports `activities/<activity_type_id>/tools.py` and calls `make_tools(_Ctx())`.
2. For each `@tool`, dumps `t.args_schema.model_json_schema()`.
3. Asserts no `anyOf` branch lacks a `type` / `$ref` / `anyOf` field
   (DeepSeek strict-mode requirement; matches E1 in
   `skills/activity-diagnostician/references/error-classes.md`).
4. Asserts no `"items": {}` empty array schema (same).
5. Prints `<tool_name>: ok` per tool, or a problem report.

Exit code 0 = all tools clean.

The script is pure stdlib + langchain (already a runtime dep); no extra
install. It mirrors the manual check used to catch an early activity's
`set_last_brief` `str | list` regression.

## Combined output contract

```markdown
## Verification
- verifier: 0 ERROR / <n> WARNING
- strict-tool-schema: <m> tool(s) ok
- ship-ready: yes / no
- pending fixes: <list, or "none">
```

`ship-ready: yes` requires both checks at 0 errors. WARNINGs are listed but
don't flip the gate; they get acknowledged in the packager's Ship Verification
block.

This skill is static-only. The Ship Verification gate additionally always
requires the offline **testkit smoke** (`python <package>/testkit/fda_testkit.py
activities/<id>`, no platform repo needed) — see
[workflows/06-verify-and-ship.md](../../workflows/06-verify-and-ship.md) step 3.5.

## When to run

- After every `activity-builder` scaffold pass.
- After any edit (via `activity-builder`) to `tools.py`, `data.schema.json`,
  `manifest.json`, `runtime.json`, or any `card_templates/*.json`.
- As the first step of `activity-packager` re-pack mode.
- After applying a fix proposed by `activity-diagnostician`.

## Hand-off

- `ship-ready: yes` → route to `activity-packager`.
- `ship-ready: no` → for each pending fix, route to `activity-diagnostician`
  to map the error to a class, then `activity-builder` to apply the fix.

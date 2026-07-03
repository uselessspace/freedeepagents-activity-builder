# Reference — Activity Python dependencies (`requirements.txt`)

> **Single source of truth** for how an activity declares the third-party
> Python packages its `tools.py` / `dsl_builder.py` / `handlers.py` (and any
> helper modules they ship) need. The runtime that consumes this file:
> `app/dev_sync.py` (uv-installs on upload), the repo `Dockerfile` (bakes it
> at image build), and `tools/install-activity.sh` (local install). The
> activity verifier (`tools/activity_verifier.py`) enforces completeness.

## Contents

- The rule · why per-activity & complete · what (NOT) to declare
- Format & discipline · prefer stdlib/capability first
- How installation happens · the verifier check

## The rule

Each activity that imports any third-party Python package **must** declare it
in `activities/<id>/requirements.txt`. One pinned requirement per line.

```
# activities/<id>/requirements.txt
akshare==1.16.0
pandas==2.2.3
```

No third-party imports → no `requirements.txt` needed.

## Why per-activity, and why it must be complete

All activities load into the host's **single shared Python venv** — there is no
per-activity isolation (unlike the frontend, where each activity gets its own
`node_modules`). The runtime loads `tools.py` via `spec_from_file_location` +
`exec_module` straight into the main uvicorn process (`app/activity_tools.py`).
So:

- A package you import but don't declare is **not installed on a fresh host** →
  the activity `ImportError`s the first time that import runs. The verifier
  blocks this before it ships.
- Because the venv is shared, **a dependency you add is global**. It can collide
  with the platform's own pins or another activity's. Add as few as possible
  (see "Prefer stdlib or a capability" below).

## What to declare — and what NOT to

Do **not** declare (the verifier already treats these as available):

- **Python stdlib** — `json`, `pathlib`, `datetime`, `asyncio`, … never go in
  `requirements.txt`.
- **The platform baseline** — everything the host's own `requirements.txt`
  pulls in transitively: `langchain*`, `fastapi`, `pydantic`, `httpx`,
  `openai`, `numpy`, `pandas`, `jinja2`, `bs4`, … The authoritative list is
  [runtime-python-baseline.txt](runtime-python-baseline.txt) (generated; the
  verifier reads it).
- **First-party `app.*`** — `from app.something import x` is the host package,
  always importable.
- **Sibling modules you ship** — a helper like `_graph.py`, or a skill
  `scripts/` module imported after a `sys.path` insert, is local, not a
  dependency.

**Declare** everything else you `import`: `PyPDF2`, `pymupdf`, `akshare`,
`graphiti-core`, `kuzu`, `pypinyin`, … If `import foo` doesn't resolve to one of
the four categories above, it needs a line.

## Format & discipline

1. **Pin versions** with `==` for reproducibility. `akshare==1.16.0`, not
   `akshare` or `akshare>=1.16`. A floating pin means two installs of the same
   activity can resolve to different code.
2. **One requirement per line**; `#` comments are encouraged. Group related
   deps under a comment header explaining *what activity feature needs them*:

   ```text
   # 关系图谱抽取（graph_build 工具用）
   networkx==3.4.2
   # PDF 文本层解析（import_document 工具用；解析失败时降级 read_document）
   pymupdf==1.24.10
   ```
3. **Lazy-import heavy deps** inside the function that uses them, not at module
   top level:

   ```python
   def extract_pdf_text(path: str) -> str:
       import pymupdf  # lazy: only the PDF path pays the import cost
       ...
   ```

   This keeps cold start cheap and lets an activity degrade gracefully when an
   optional path isn't exercised. (You still declare the package — lazy import
   is about startup cost, not about skipping the declaration.)
4. **System (non-pip) dependencies** — pip can't install `ffmpeg`, `poppler`,
   etc. If your code shells out to one, record it as a `# system: ffmpeg` line
   so whoever provisions the host image knows. pip-only requirements.txt cannot
   pull these in.

## Prefer stdlib or a capability before adding a dependency

Because the venv is shared and global, treat a new third-party package as a
cost, not a convenience. Before adding one, ask:

- Can the **stdlib** do it? (`urllib`/`http`, `csv`, `sqlite3`, `zipfile`,
  `hashlib`, …)
- Does a **runtime capability** already cover it? Image generation/editing,
  TTS, and document→Markdown reading are provided by the platform via
  `manifest.capabilities` — see [capabilities.md](../policies/capabilities.md).
  Don't vendor your own image or PDF-reading stack when a capability exists.

Only add a real third-party package when neither fits.

## How it gets installed (you don't run the installer yourself)

The runtime venv has no `pip` module, so installs go through **uv**
(`uv pip install -p <interpreter> -r requirements.txt`), falling back to
`python -m pip` only where uv is unavailable.

| Path | When | Mechanism |
|---|---|---|
| `POST /dev/sync` upload | on every upload where `requirements.txt` changed | `uv pip install -p <interpreter> -r requirements.txt` into the host venv, pip fallback (`app/dev_sync.py::_py_install_cmd`) |
| Runtime startup | when host activities already exist | uv installs changed `activities/*/requirements.txt` into the running interpreter and records `runtime/activity-dependencies.json` |
| `tools/install-activity.sh` | local `.fda.tgz` install | uv (pip fallback) installs the activity's `requirements.txt` after extraction |

`pack-activity.sh` bundles `requirements.txt` automatically (it lives under
`activities/<id>/`).

## The verifier check

`tools/activity_verifier.py` AST-scans every runtime `.py` an activity ships
(excluding `site/`, tests, and `__pycache__`) and reports any top-level import
that is **not** stdlib, baseline, first-party, a local module, or declared in
the activity's `requirements.txt`:

```
ERROR activities/<id>/tools.py: imports third-party package 'pymupdf' but it is
not declared in activities/<id>/requirements.txt ...
```

The scan also covers skill `scripts/*.py`. If such a script is only ever run
inside the Docker sandbox (not loaded into the host process) and pulls a package
the host never needs, the simplest fix is still to declare it in the activity's
`requirements.txt` — declaring a package the host doesn't import is harmless, and
it keeps the sandbox and host environments consistent.

To satisfy it: add a pinned line for the package. If the import is genuinely a
**platform** dependency that the baseline is missing (e.g. you added it to the
host's own `requirements.txt`), regenerate the baseline instead:

```bash
.venv/bin/python <package>/tools/gen-python-baseline.py
```

(Run from the FDA repo root with the runtime venv active. Re-run whenever the
host `requirements.txt` changes.)

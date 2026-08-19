# Project-local Python environment

Use this preflight before running Builder Python tools. The objective is a
reproducible development interpreter without modifying global Python or
placing environment files in the uploaded activity.

## Ownership

- Put the authoring environment at `<project-root>/.venv`.
- Never create it under `activities/<activity_type_id>/` or inside a separate
  installed plugin/cache that is not the project root.
- `<builder-root>` and `<project-root>` may be the same writable standalone
  checkout; in that case its root `.venv` is still the project environment.
- Ensure `<project-root>/.gitignore` contains `.venv/`.
- Managed runtime downloads, when needed, live in `<project-root>/.fda-tools/`;
  keep that directory ignored as well.
- Invoke the environment's Python by explicit path; activation is optional.
- Current FDA targets Python 3.12. If another runtime is the deployment target,
  its `pyproject.toml`, `.python-version`, and pinned requirements win.

In Builder commands, `<project-python>` means that explicit project `.venv`
interpreter (`.venv/bin/python` on macOS/Linux or
`.venv\Scripts\python.exe` on Windows). `<runtime-python>` means the target
FreeDeepAgents repository's fully provisioned interpreter and is used only by
checks that import runtime `app.*`.

## Coding Agent decision flow

1. Resolve `<project-root>` and the target runtime's Python minor version.
2. Inspect `<project-root>/.venv` without changing it. Reuse it only when its
   interpreter matches the target minor version and the required command runs.
3. If `.venv` is absent, create it in `<project-root>` with an already-installed
   matching interpreter.
4. If `.venv` exists but is incompatible, do not overwrite or delete it. Report
   the detected version and ask before replacing or choosing another directory.
5. If the matching base interpreter is absent, use the bundled bootstrap script
   after telling the user it will download a checksum-verified runtime from the
   configured domestic mirror into `<project-root>/.fda-tools/`. Running that
   command is the visible authorization boundary; it never needs administrator
   privileges or changes the system Python.
6. Install only dependencies needed by the next check, using target-runtime
   pins. Never run an unbounded `pip install -U`.

## Recommended bootstrap

The scripts reuse a compatible `.venv` first. If Python 3.12 is unavailable,
they install pinned CPython 3.12.13 from npmmirror into the project-local
`.fda-tools/` directory, verify the published SHA-256 checksum, create `.venv`,
and configure pip to use the Tsinghua mirror. No overseas source is used by
default and there is no `curl | sh`, global package install, or administrator
mutation.

macOS / Linux:

```bash
bash <builder-root>/tools/bootstrap-authoring-env.sh \
  --project-root <project-root>
```

Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<builder-root>\tools\bootstrap-authoring-env.ps1" -ProjectRoot "<project-root>"
```

Replace both placeholders with real absolute paths. The scripts refuse to
overwrite an incompatible or incomplete `.venv` / managed runtime. They also
write `.fda-tools/authoring-env.sh` or `authoring-env.ps1`; source that file in
a new shell to restore the project-local PATH and domestic pip/npm indexes.
The Windows command's `Bypass` is process-only and does not persistently change
execution policy. An enforced organization Group Policy still wins; do not
weaken it—ask the administrator when it blocks the script.

Defaults can be replaced by an enterprise mirror without editing the script:

```text
FDA_PYTHON_MIRROR  Python standalone release root
FDA_PIP_INDEX      Python package index URL
```

For a non-current FDA target whose runtime does not use Python 3.12, do not run
this pinned bootstrap unchanged. Follow that runtime repository's own version
and environment setup instead.

## Install only the needed layer

The bundled verifier is stdlib-only. A compatible interpreter is enough:

```text
<project-python> <builder-root>/tools/activity_verifier.py <project-root>
```

The offline testkit has no dependencies of its own, but importing an
activity's `tools.py` may need target-baseline modules such as
`langchain_core`, plus packages declared by that activity. For Builder 0.4.41
and the current FDA baseline, use the validated pins rather than an old
LangChain major:

```text
<project-python> -m pip install "deepagents==0.7.3" "langchain-core==1.5.3"
<project-python> -m pip install -r activities/<activity_type_id>/requirements.txt  # only when present
```

If `pip` is intentionally absent and `uv` is already available, use
`uv pip install -p <project-python> ...` with the same pins. Any network-backed
install remains a visible project setup action.

When `<project-root>` is the target FreeDeepAgents runtime repository, prefer
that repository's normal pinned environment setup instead of the lightweight
commands above. Its project-local `.venv` must contain the full runtime before
running `strict-tool-schema-check.py`, because that check imports `app.*`.
An activity-only project cannot manufacture that runtime context; use the
offline testkit coverage and record the strict check as covered by testkit.

## Evidence

Record the interpreter path and version in `Development Verification`, plus
whether the environment was reused or created. Do not report environment
success merely because `.venv/` exists.

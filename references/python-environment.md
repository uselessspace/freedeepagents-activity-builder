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
5. If the matching base interpreter is absent, stop and ask the user to install
   or authorize installation of it. Do not silently use an older Python, install
   system-wide packages, or let a tool download an interpreter without notice.
6. Install only dependencies needed by the next check, using target-runtime
   pins. Never run an unbounded `pip install -U`.

## Create or verify the environment

macOS / Linux, from `<project-root>`:

```bash
if [ -x .venv/bin/python ]; then
  .venv/bin/python -c 'import sys; print(sys.executable, sys.version)'
else
  python3.12 -m venv .venv
  .venv/bin/python -c 'import sys; assert sys.version_info[:2] == (3, 12); print(sys.executable)'
fi
```

Windows PowerShell, from `<project-root>`:

```powershell
if (Test-Path ".venv\Scripts\python.exe") {
  & ".venv\Scripts\python.exe" -c "import sys; print(sys.executable, sys.version)"
} else {
  py -3.12 -m venv .venv
  & ".venv\Scripts\python.exe" -c "import sys; assert sys.version_info[:2] == (3, 12); print(sys.executable)"
}
```

These snippets inspect an existing environment but deliberately do not
overwrite an incompatible one. Check the printed version before continuing.
For a non-current FDA target, substitute its required Python minor version.

## Install only the needed layer

The bundled verifier is stdlib-only. A compatible interpreter is enough:

```text
<project-python> <builder-root>/tools/activity_verifier.py <project-root>
```

The offline testkit has no dependencies of its own, but importing an
activity's `tools.py` may need target-baseline modules such as
`langchain_core`, plus packages declared by that activity. For Builder 0.4.36
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

# Reference — Splitting an activity backend across Python files

When `tools.py` / `handlers.py` / `dsl_builder.py` grows, move shared logic into
your own helper `.py` files next to it (e.g. `discussion.py`, `llm_helpers.py`,
`image_helpers.py`). This keeps each entrypoint thin and lets the @tool surface
and the SPA handlers share one implementation.

## How to import things

Inside any activity Python file:

- **Standard library, third-party, and runtime code** — use a normal `import`:
  `import json`, `import httpx`, `from app.card_system import data_store`,
  `from langchain_core.tools import tool`. (Third-party packages must be
  declared — see [python-dependencies.md](python-dependencies.md).)
- **Your own sibling helper files** — load them by file path with the small
  helper below. The runtime loads `tools.py` / `handlers.py` / `dsl_builder.py`
  by file path (so they can be hot-reloaded), which means they have no package
  context for `import sibling` to resolve — loading by path is the reliable way
  to reach a neighbour file.

## Canonical sibling loader

Copy this into the entrypoint that needs a helper:

```python
import importlib.util
import sys
from pathlib import Path


def _load_helper(filename: str):
    """Load a sibling .py helper by file path.

    Re-reads the file from disk on every call, so when dev_sync hot-syncs an
    edit to the helper (e.g. a prompt change in discussion.py) it goes live on
    the next turn — no uvicorn restart needed. Keep helpers stateless (pure
    functions + constants) so re-loading is cheap and side-effect free.
    """
    path = Path(__file__).resolve().parent / filename
    spec = importlib.util.spec_from_file_location(f"_acthelper_{path.stem}", path)
    module = importlib.util.module_from_spec(spec)
    # Register before exec so a helper that imports itself resolves cleanly.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


# Bind what you need at module top level:
discussion = _load_helper("discussion.py")
call_json_llm = _load_helper("llm_helpers.py").call_json_llm
```

## Keep helpers stateless

Helpers re-load each turn (the runtime already re-executes `tools.py` /
`handlers.py` per turn — costs almost nothing; `import httpx` etc. inside a
helper still hit Python's import cache). So treat helpers as pure modules:
functions, constants, prompt strings. Per-instance state goes in typed-KV
([data-store-tools.md](data-store-tools.md)) or the instance directory, never
module-level globals — that's also what makes prompt edits land instantly: the
value of the file *is* its current contents on disk.

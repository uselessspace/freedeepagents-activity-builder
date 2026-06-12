# FDA activity testkit

Run an activity's Python **locally, without the FreeDeepAgents platform repo**.

External developers don't have `app.card_system` / `app.errors` checked out, so
their `tools.py` (`make_tools`) and `dsl_builder.py` (`build`) can't be imported
or run offline. [`fda_testkit.py`](fda_testkit.py) is a single self-contained
file that stubs those modules with faithful, temp-dir-backed, schema-validating
implementations.

**Python**: ≥ 3.9 (tested floor; 3.10+ fine). The testkit itself has zero
third-party deps; importing *your* `tools.py` still needs whatever it imports
(typically `langchain_core` — any 0.3.x works). Note the bundled verifier has a
higher floor (≥ 3.10), see `INSTALL.md` "Toolchain requirements".

## What it covers vs the verifier

| | `tools/activity_verifier.py` | `testkit/fda_testkit.py` |
|---|---|---|
| Card template / vars **files** valid? | ✅ static, zero-dep | — (run the verifier) |
| `make_tools(ctx)` actually **builds**? | — | ✅ imports + runs it |
| Each tool's arg schema strict-safe? | — (separate strict-check script) | ✅ flags empty `items:{}` |
| `dsl_builder.build()` runs + returns JSON? | — | ✅ against a seeded temp instance |
| Data-store writes pass `data.schema.json`? | — | ✅ validated on every write |

The verifier checks files; the testkit **runs your code**. Use both.

## CLI smoke

```bash
python testkit/fda_testkit.py path/to/activities/<id>
```

```
==> smoking bedtime-story
  make_tools(): ok — 7 tool(s): ['clear_today_brief', 'delete_story', ...]
  dsl_builder.build(): ok — returned dict with keys ['archive', 'source', 'tonight', ...]
✓ smoke clean
```

Exit code is non-zero if `make_tools` / `build` raise, a tool has a
strict-mode-illegal `items:{}` schema, or `build` returns non-JSON.

## In your own pytest

```python
import sys; sys.path.insert(0, "packages/freedeepagents-activity-builder/testkit")
from fda_testkit import load_make_tools, activity_harness

def test_tools_build():
    tools = load_make_tools("activities/my-activity")
    assert {t.name for t in tools} >= {"save_thing"}

def test_tool_writes_validate():
    with activity_harness("activities/my-activity") as ctx:
        tools = {t.name: t for t in __import__("tools").make_tools(ctx)}
        out = tools["save_thing"].invoke({"title": "x"})
        assert out["ok"] is True
```

`activity_harness` installs the stubs, seeds a temp instance from
`data.schema.json`'s top-level `default`, and yields a `FakeCtx`
(`instance_dir` / `activity_dir` / `notify_dsl_update` / `turn_files` /
`llm` — always `None` offline; assign a duck-typed fake to test
LLM-dependent paths, see [references/ctx-llm.md](../references/ctx-llm.md)).

The `update_data` stub mirrors the platform contract exactly: the mutator
may return a plain `dict` **or** a `(dict, side_info)` tuple — both are
legal in production (`app/card_system/data_store.py`).

## Fidelity & limits

- The data-store stub validates every write against `data.schema.json` with the
  same JSON-Schema subset the packaged verifier uses — a write your activity
  rejects in production is rejected here too.
- It does **not** run the LLM, the sandbox, card rendering, or image/tts
  capabilities. It exercises the deterministic Python: tool construction, tool
  bodies that only touch the data store, and the DSL builder.
- Zero third-party deps of its own; `make_tools` import still needs whatever
  your `tools.py` imports (typically `langchain_core`).

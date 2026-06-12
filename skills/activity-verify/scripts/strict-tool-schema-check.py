#!/usr/bin/env python3
"""Static check: every activity @tool param schema is DeepSeek-strict-clean.

Walks the activity's tools.py, calls make_tools(_FakeCtx()), and inspects
each tool's args_schema.model_json_schema() for the two known footguns:

  1. anyOf branch missing `type` / `$ref` / `anyOf`
     (caused by `X | None` is fine; `str | list` is NOT)
  2. `array.items` schema is `{}` (empty)
     (caused by `items: list` annotation without item type)

Both are the cause class for E1 in
``skills/activity-diagnostician/references/error-classes.md``.

Exits 0 if all tools pass, 1 otherwise. Pure stdlib + langchain_core
(already a runtime dep).

Usage (use the FDA repo's Python — a plain `python3` on PATH usually lacks
``langchain_core`` which activity tools.py imports transitively)::

    .venv/bin/python strict-tool-schema-check.py --activity <activity_type_id> [--repo <path>]
    .venv/bin/python strict-tool-schema-check.py --tools-py <path/to/tools.py>
    # or, with uv:
    uv run python strict-tool-schema-check.py --activity <activity_type_id>

The first form auto-detects the repo root via git, then loads
``<repo>/activities/<id>/tools.py``. The second is for ad-hoc files.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import pathlib
import subprocess
import sys


class _FakeCtx:
    """Minimal context object that ``make_tools(ctx)`` typically pokes at.

    Real ctx has instance_dir / activity_dir / notify_dsl_update. Tools may
    capture these in closures but won't invoke them at make_tools() time —
    they're called per-invocation. A fake with dummy paths is enough to
    instantiate the @tool functions and read their args_schema.
    """

    def __init__(self, activity_dir: pathlib.Path):
        self.instance_dir = pathlib.Path("/tmp/_strict_check_instance")
        self.activity_dir = activity_dir

    def notify_dsl_update(self) -> None:
        pass


def _find_repo_root(explicit: str | None) -> pathlib.Path:
    if explicit:
        return pathlib.Path(explicit).resolve()
    try:
        out = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        return pathlib.Path(out)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return pathlib.Path.cwd()


def _load_make_tools(tools_py: pathlib.Path):
    spec = importlib.util.spec_from_file_location(f"_strict_check_{tools_py.stem}", tools_py)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load module from {tools_py}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    if not hasattr(mod, "make_tools"):
        raise RuntimeError(f"{tools_py} has no make_tools(ctx) callable")
    return mod.make_tools


def _check_schema(name: str, schema: dict) -> list[str]:
    """Return list of problem descriptions; empty list means clean.

    Walks the entire schema unconditionally and flags every anyOf branch
    that lacks ``type`` / ``$ref`` / ``anyOf``. A previous version
    short-circuited the walk when the schema blob contained any
    ``"type":"null"``, which silently let a broken anyOf in one parameter
    slip through whenever a sibling parameter happened to use ``str | None``.
    """
    problems: list[str] = []

    def walk(node, path="$"):
        if isinstance(node, dict):
            if "anyOf" in node:
                for i, branch in enumerate(node["anyOf"]):
                    if not isinstance(branch, dict):
                        problems.append(f"{path}.anyOf[{i}] is not an object")
                        continue
                    if not any(k in branch for k in ("type", "$ref", "anyOf")):
                        problems.append(
                            f"{path}.anyOf[{i}] has no type/$ref/anyOf field (branch keys: {sorted(branch.keys())})"
                        )
            for k, v in node.items():
                walk(v, f"{path}.{k}")
        elif isinstance(node, list):
            for i, v in enumerate(node):
                walk(v, f"{path}[{i}]")

    walk(schema)

    # Empty array items — pydantic produces this when a parameter is annotated
    # as bare `list` / `dict` without an item type. DeepSeek strict mode rejects
    # the empty `{}` items schema for the same reason it rejects untyped anyOf
    # branches. Detect both compact and indented JSON serializations.
    blob = json.dumps(schema)
    if '"items": {}' in blob or '"items":{}' in blob:
        problems.append("array param has empty `items: {}` schema (use a concrete item type or accept JSON string)")
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--activity", help="activity_id; tools.py looked up under <repo>/activities/<id>/")
    g.add_argument("--tools-py", help="explicit path to a tools.py file")
    ap.add_argument("--repo", help="repo root override (default: git rev-parse --show-toplevel)")
    args = ap.parse_args()

    if args.activity:
        repo = _find_repo_root(args.repo)
        tools_py = repo / "activities" / args.activity / "tools.py"
    else:
        tools_py = pathlib.Path(args.tools_py).resolve()
        repo = _find_repo_root(args.repo)

    if not tools_py.is_file():
        print(f"error: tools.py not found at {tools_py}", file=sys.stderr)
        return 2

    # Activity tools commonly `from app.card_system import data_store`; the
    # FDA repo root must be on sys.path so that import resolves. The check
    # itself only needs the @tool decorators (which add the activity tool to
    # langchain's registry); no card_system call happens at make_tools() time.
    if str(repo) not in sys.path:
        sys.path.insert(0, str(repo))

    activity_dir = tools_py.parent
    make_tools = _load_make_tools(tools_py)
    ctx = _FakeCtx(activity_dir)
    tools = make_tools(ctx)

    failed = 0
    print(f"==> Checking {len(tools)} tool(s) in {tools_py}")
    for t in tools:
        name = getattr(t, "name", repr(t))
        schema = t.args_schema.model_json_schema() if getattr(t, "args_schema", None) else {}
        problems = _check_schema(name, schema)
        if problems:
            failed += 1
            print(f"  {name}: FAIL")
            for p in problems:
                print(f"    - {p}")
        else:
            print(f"  {name}: ok")

    if failed:
        print(f"\n{failed}/{len(tools)} tool(s) failed strict-mode schema check.")
        print(
            "Fix path: narrow Union types to `str | None` only; give containers a "
            "concrete item type (`list[str]` / `list[dict]` both pass — never bare "
            "`list`/`dict`), or accept a JSON-encoded string and parse inside the "
            "function. See policies/llm-output-discipline.md §8d."
        )
        return 1

    print(f"\nAll {len(tools)} tool(s) passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

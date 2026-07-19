#!/usr/bin/env python3
"""FDA activity testkit — exercise an activity's Python locally, no platform repo.

External activity developers don't have the FreeDeepAgents runtime checked out,
so they can't import ``app.card_system`` / ``app.errors`` that their
``tools.py`` (``make_tools``) and ``dsl_builder.py`` (``build``) depend on. This
single self-contained file stubs those modules with faithful, temp-dir-backed
implementations so you can smoke your activity offline:

    # one-shot CLI smoke (build make_tools + run dsl_builder.build):
    python testkit/fda_testkit.py path/to/activities/<id>

    # or in your own pytest:
    from fda_testkit import activity_harness, load_make_tools
    def test_tools_build():
        tools = load_make_tools("activities/my-activity")
        assert {t.name for t in tools} >= {"save_thing"}

What it gives you that the verifier doesn't: the verifier statically validates
files; this actually IMPORTS and RUNS your make_tools/build against a seeded
in-memory data store (schema-validated on every write, same as production), so a
KeyError in build() or a schema-rejecting data_set in a tool surfaces locally.

Zero third-party dependencies (stdlib + langchain only when your tools.py needs
it). The data-store stub validates writes with the same JSON-Schema subset the
packaged ``tools/activity_verifier.py`` uses, so a write your activity rejects
in production is rejected here too.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import importlib.util
import json
import re
import sys
import tempfile
import threading
import types
from collections.abc import Callable
from pathlib import Path
from typing import Any


# ── error types (mirror app/errors.py) ───────────────────────────────────────
class AppError(Exception):
    def __init__(self, message: str, *, status_code: int = 500, hint: str | None = None) -> None:
        super().__init__(message)
        self.message = message
        self.status_code = status_code
        self.hint = hint


class OutputValidationError(AppError):
    pass


# ── JSON-Schema subset validator (mirrors app/json_schema.py keyword-for-keyword
#    so a data.schema.json write rejected in production is rejected here too) ───
_TYPES_MAP = {
    "object": dict,
    "array": list,
    "string": str,
    "boolean": bool,
    "number": (int, float),
    "integer": int,
    "null": type(None),
}


def _type_matches(value: Any, expected: str) -> bool:
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    py = _TYPES_MAP.get(expected)
    return True if py is None else isinstance(value, py)


def _resolve_ref(root_schema: Any, ref: str) -> Any:
    if not isinstance(ref, str) or not ref.startswith("#/"):
        raise AppError(f"unsupported $ref {ref!r}; only local '#/…' refs supported", status_code=400)
    current = root_schema
    for raw in ref[2:].split("/"):
        part = raw.replace("~1", "/").replace("~0", "~")
        if not isinstance(current, dict) or part not in current:
            raise AppError(f"unresolved $ref {ref!r}", status_code=400)
        current = current[part]
    return current


def _validate_json_schema(
    value: Any, schema: Any, *, root_schema: Any = None, path: str = "$", refs: tuple = ()
) -> None:
    if root_schema is None:
        root_schema = schema
    if schema is True or schema == {}:
        return
    if schema is False:
        raise AppError(f"{path}: value not allowed", status_code=400)
    if not isinstance(schema, dict):
        return
    if "$ref" in schema:
        ref = schema["$ref"]
        if ref not in refs:
            _validate_json_schema(
                value, _resolve_ref(root_schema, ref), root_schema=root_schema, path=path, refs=(*refs, ref)
            )
    if "const" in schema and value != schema["const"]:
        raise AppError(f"{path}: expected const {schema['const']!r}", status_code=400)
    if "enum" in schema and value not in schema["enum"]:
        raise AppError(f"{path}: {value!r} not in enum {schema['enum']!r}", status_code=400)
    if "allOf" in schema:
        for opt in schema["allOf"]:
            _validate_json_schema(value, opt, root_schema=root_schema, path=path, refs=refs)
    if "anyOf" in schema:
        errs = []
        for opt in schema["anyOf"]:
            try:
                _validate_json_schema(value, opt, root_schema=root_schema, path=path, refs=refs)
                break
            except AppError as exc:
                errs.append(str(exc))
        else:
            raise AppError(f"{path}: no anyOf branch matched ({errs[:2]})", status_code=400)
    if "oneOf" in schema:
        matched = 0
        for opt in schema["oneOf"]:
            try:
                _validate_json_schema(value, opt, root_schema=root_schema, path=path, refs=refs)
                matched += 1
            except AppError:
                pass
        if matched != 1:
            raise AppError(f"{path}: expected exactly one oneOf match, got {matched}", status_code=400)

    t = schema.get("type")
    expected = t if isinstance(t, list) else [t] if t else []
    if expected and not any(_type_matches(value, e) for e in expected):
        raise AppError(f"{path}: expected type {t!r}, got {type(value).__name__}", status_code=400)

    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                raise AppError(f"{path}.{key}: required property missing", status_code=400)
        props = schema.get("properties", {}) or {}
        for k, v in value.items():
            if k in props:
                _validate_json_schema(v, props[k], root_schema=root_schema, path=f"{path}.{k}", refs=refs)
        ap = schema.get("additionalProperties", True)
        extra = sorted(set(value) - set(props))
        if ap is False and extra:
            raise AppError(f"{path}: unexpected properties {extra!r}", status_code=400)
        if isinstance(ap, dict):
            for k in extra:
                _validate_json_schema(value[k], ap, root_schema=root_schema, path=f"{path}.{k}", refs=refs)

    if isinstance(value, list):
        min_items, max_items = schema.get("minItems"), schema.get("maxItems")
        if isinstance(min_items, int) and len(value) < min_items:
            raise AppError(f"{path}: expected at least {min_items} items", status_code=400)
        if isinstance(max_items, int) and len(value) > max_items:
            raise AppError(f"{path}: expected at most {max_items} items", status_code=400)
        if schema.get("uniqueItems") is True:
            seen = []
            for item in value:
                if item in seen:
                    raise AppError(f"{path}: expected unique items", status_code=400)
                seen.append(item)
        items = schema.get("items")
        if isinstance(items, (dict, bool)):
            for i, item in enumerate(value):
                _validate_json_schema(item, items, root_schema=root_schema, path=f"{path}[{i}]", refs=refs)

    if isinstance(value, str):
        min_len, max_len = schema.get("minLength"), schema.get("maxLength")
        if isinstance(min_len, int) and len(value) < min_len:
            raise AppError(f"{path}: expected string length >= {min_len}", status_code=400)
        if isinstance(max_len, int) and len(value) > max_len:
            raise AppError(f"{path}: expected string length <= {max_len}", status_code=400)
        pattern = schema.get("pattern")
        if isinstance(pattern, str) and re.search(pattern, value) is None:
            raise AppError(f"{path}: expected string to match pattern {pattern!r}", status_code=400)

    if isinstance(value, (int, float)) and not isinstance(value, bool):
        for kw, op, sym in (
            ("minimum", value.__lt__, "<"),
            ("maximum", value.__gt__, ">"),
        ):
            bound = schema.get(kw)
            if isinstance(bound, (int, float)) and op(bound):
                raise AppError(f"{path}: {value} {sym} {kw} {bound}", status_code=400)
        emin, emax = schema.get("exclusiveMinimum"), schema.get("exclusiveMaximum")
        if isinstance(emin, (int, float)) and value <= emin:
            raise AppError(f"{path}: expected number > {emin}", status_code=400)
        if isinstance(emax, (int, float)) and value >= emax:
            raise AppError(f"{path}: expected number < {emax}", status_code=400)
        mult = schema.get("multipleOf")
        if isinstance(mult, (int, float)) and mult and value % mult != 0:
            raise AppError(f"{path}: expected multiple of {mult}", status_code=400)


# ── temp-dir-backed data store (mirror app/card_system/data_store.py surface) ─
_locks: dict[str, threading.Lock] = {}


def _lock_for(instance_dir: Path) -> threading.Lock:
    return _locks.setdefault(str(instance_dir), threading.Lock())


def _data_path(instance_dir: Path) -> Path:
    return Path(instance_dir) / "data.json"


def load_data_schema(activity_dir: Path) -> dict[str, Any]:
    schema_file = Path(activity_dir) / "data.schema.json"
    if not schema_file.exists():
        return {}
    return json.loads(schema_file.read_text(encoding="utf-8"))


def initialize_data_store(instance_dir: Path, schema: dict[str, Any]) -> None:
    p = _data_path(instance_dir)
    if not p.exists():
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(schema.get("default", {}), ensure_ascii=False, indent=2), encoding="utf-8")


def read_data(instance_dir: Path) -> dict[str, Any]:
    p = _data_path(instance_dir)
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def _write_data(instance_dir: Path, schema: dict[str, Any], data: dict[str, Any]) -> None:
    if schema:
        _validate_json_schema(data, schema)
    _data_path(instance_dir).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def update_data(instance_dir: Path, schema: dict[str, Any], mut: Callable[[dict], dict | tuple[dict, Any]]) -> Any:
    # Mirrors the platform contract (app/card_system/data_store.py): the mutator
    # may return either a plain dict (side_info -> None) or a (dict, side_info)
    # 2-tuple. Anything else is rejected the same way the runtime rejects it —
    # a dict with exactly 2 keys must NOT silently unpack as a tuple.
    with _lock_for(instance_dir):
        data = read_data(instance_dir) or json.loads(json.dumps(schema.get("default", {})))
        result = mut(data)
        if isinstance(result, tuple):
            if len(result) != 2:
                raise AppError(
                    f"update_data mutator returned a {len(result)}-tuple; expected dict or (dict, side_info)"
                )
            new_data, side = result
        else:
            new_data, side = result, None
        if not isinstance(new_data, dict):
            raise AppError(
                f"update_data mutator must return dict (or (dict, side_info)); got {type(new_data).__name__}"
            )
        _write_data(instance_dir, schema, new_data)
        return side


def set_value(instance_dir: Path, schema: dict[str, Any], key: str, value: Any) -> None:
    def mut(d):
        d[key] = value
        return d, None

    update_data(instance_dir, schema, mut)


def get_value(instance_dir: Path, key: str) -> Any:
    return read_data(instance_dir).get(key)


def append_value(instance_dir: Path, schema: dict[str, Any], key: str, value: Any) -> None:
    def mut(d):
        d.setdefault(key, []).append(value)
        return d, None

    update_data(instance_dir, schema, mut)


def delete_value(instance_dir: Path, schema: dict[str, Any], key: str) -> bool:
    def mut(d):
        existed = key in d
        d.pop(key, None)
        return d, existed

    return update_data(instance_dir, schema, mut)


def list_keys(instance_dir: Path, schema: dict[str, Any]) -> dict[str, Any]:
    return {k: {"present": True} for k in read_data(instance_dir)}


# ── stub installation + fake ctx ─────────────────────────────────────────────
class FakeCtx:
    """The subset of the runtime ctx that activity tools.py / dsl_builder use."""

    def __init__(self, activity_dir: Path, instance_dir: Path) -> None:
        self.activity_dir = Path(activity_dir)
        self.instance_dir = Path(instance_dir)
        self.turn_files: list = []
        self.promoted_turn_file_ids: list[str] = []
        self.deleted_asset_requests: list[dict[str, Any]] = []
        self.dsl_updates = 0
        # Records the activity-authored payload before production adds its
        # event_id / turn_id envelope and publishes it on preview_navigate.
        self.preview_navigation_events: list[dict[str, Any]] = []
        # Offline ctx has no LLM gateway: ctx.llm is None, exactly like a
        # minimal runtime ctx built without settings — your None-fallback
        # branch gets exercised for free. To test LLM-dependent paths,
        # assign a duck-typed fake (chat / chat_json / vision) in your test.
        # See references/ctx-llm.md.
        self.llm = None

    def notify_dsl_update(self) -> None:
        self.dsl_updates += 1

    def emit_preview_navigation(self, payload: dict[str, Any]) -> None:
        if not isinstance(payload, dict):
            raise TypeError("preview navigation payload must be a dict")
        # Prove offline that the payload can cross the runtime JSON boundary.
        self.preview_navigation_events.append(json.loads(json.dumps(payload)))

    def promote_turn_file(self, file_id: str) -> dict[str, Any]:
        """Return a JSON-safe instance asset handle and record the promotion.

        Offline tests do not persist media bytes. The deterministic handle is
        sufficient for exercising activity reference migration and cleanup
        policy without a platform storage backend.
        """
        if not isinstance(file_id, str) or not file_id:
            raise AppError("file_id must be a non-empty string", status_code=400)
        digest = hashlib.sha256(file_id.encode("utf-8")).hexdigest()
        upload_name = f"{digest}.png"
        self.promoted_turn_file_ids.append(file_id)
        activity_type_id = self.activity_dir.name
        activity_id = self.instance_dir.name
        return {
            "asset_id": upload_name,
            "upload_name": upload_name,
            "url": f"/preview/{activity_type_id}/{activity_id}/uploads/{upload_name}",
            "content_type": "image/png",
            "byte_size": 0,
            "sha256": digest,
            "resource_ref": {
                "kind": "upload",
                "activity_type_id": activity_type_id,
                "activity_id": activity_id,
                "upload_name": upload_name,
            },
        }

    def delete_asset(self, *, upload_name: str, purge_origin: bool = False) -> dict[str, Any]:
        """Record an instance-scoped cleanup request for offline assertions."""
        if not isinstance(upload_name, str) or re.fullmatch(r"[0-9a-f]{64}\.[a-z0-9]+", upload_name) is None:
            raise AppError("upload_name must be a content-addressed asset name", status_code=400)
        request = {"upload_name": upload_name, "purge_origin": bool(purge_origin)}
        self.deleted_asset_requests.append(request)
        return {
            "ok": True,
            "deleted": True,
            "pending": False,
            "upload_name": upload_name,
            "reclaimed_bytes": 0,
            "origins_deleted": 1 if purge_origin else 0,
        }


def _install_stub_modules() -> None:
    """Register stub app.* modules in sys.modules so activity imports resolve."""
    if "app.card_system.data_store" in sys.modules:
        return
    app_mod = sys.modules.setdefault("app", types.ModuleType("app"))
    app_mod.__path__ = []  # mark as package

    errors_mod = types.ModuleType("app.errors")
    errors_mod.AppError = AppError
    errors_mod.OutputValidationError = OutputValidationError
    sys.modules["app.errors"] = errors_mod
    app_mod.errors = errors_mod

    cs_mod = types.ModuleType("app.card_system")
    cs_mod.__path__ = []
    sys.modules["app.card_system"] = cs_mod
    app_mod.card_system = cs_mod

    ds_mod = types.ModuleType("app.card_system.data_store")
    for fn in (
        load_data_schema,
        initialize_data_store,
        read_data,
        update_data,
        set_value,
        get_value,
        append_value,
        delete_value,
        list_keys,
    ):
        setattr(ds_mod, fn.__name__, fn)
    sys.modules["app.card_system.data_store"] = ds_mod
    cs_mod.data_store = ds_mod


@contextlib.contextmanager
def activity_harness(activity_dir: str | Path):
    """Install app.* stubs + a seeded temp instance; yield a FakeCtx.

    The instance's data.json is initialized from data.schema.json's top-level
    ``default`` so reads/writes behave like a fresh production instance.
    """
    activity_dir = Path(activity_dir).resolve()
    _install_stub_modules()
    with tempfile.TemporaryDirectory(prefix="fda-testkit-") as tmp:
        instance_dir = Path(tmp) / "instance"
        instance_dir.mkdir(parents=True)
        schema = load_data_schema(activity_dir)
        initialize_data_store(instance_dir, schema)
        yield FakeCtx(activity_dir, instance_dir)


def _load_module(path: Path, mod_name: str):
    spec = importlib.util.spec_from_file_location(mod_name, path)
    if spec is None or spec.loader is None:
        raise AppError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_make_tools(activity_dir: str | Path, *, tools_module: str = "tools") -> list:
    """Import the activity's tools.py and return make_tools(ctx)'s tool list."""
    activity_dir = Path(activity_dir).resolve()
    with activity_harness(activity_dir) as ctx:
        sys.path.insert(0, str(activity_dir))
        try:
            module = _load_module(activity_dir / f"{tools_module}.py", f"_fda_{tools_module}")
            return list(module.make_tools(ctx))
        finally:
            with contextlib.suppress(ValueError):
                sys.path.remove(str(activity_dir))


# ── CLI smoke ─────────────────────────────────────────────────────────────────
_EMPTY_ITEMS_RE = re.compile(r'"items"\s*:\s*\{\s*\}')


def _smoke(activity_dir: Path) -> int:
    manifest = json.loads((activity_dir / "manifest.json").read_text(encoding="utf-8"))
    failures = 0
    print(f"==> smoking {activity_dir.name}")

    tools_module = manifest.get("tools_module")
    if tools_module:
        try:
            tools = load_make_tools(activity_dir, tools_module=tools_module)
            print(f"  make_tools(): ok — {len(tools)} tool(s): {sorted(t.name for t in tools)}")
            for t in tools:
                schema = t.args_schema.model_json_schema() if getattr(t, "args_schema", None) else {}
                if _EMPTY_ITEMS_RE.search(json.dumps(schema)):
                    print(f"    ⚠ {t.name}: has empty `items: {{}}` — strict tool-call mode rejects it (§8d)")
                    failures += 1
        except Exception as exc:  # noqa: BLE001
            print(f"  make_tools(): FAIL — {type(exc).__name__}: {exc}")
            failures += 1
    else:
        print("  make_tools(): skipped (no tools_module in manifest)")

    dsl_module = manifest.get("dsl_builder_module")
    if dsl_module:
        try:
            with activity_harness(activity_dir) as ctx:
                sys.path.insert(0, str(activity_dir))
                try:
                    module = _load_module(activity_dir / f"{dsl_module}.py", f"_fda_{dsl_module}")
                    dsl = module.build(ctx.instance_dir)
                finally:
                    with contextlib.suppress(ValueError):
                        sys.path.remove(str(activity_dir))
            json.dumps(dsl)  # must be JSON-serializable
            print(f"  dsl_builder.build(): ok — returned {type(dsl).__name__} with keys {sorted(dsl)[:8]}")
        except Exception as exc:  # noqa: BLE001
            print(f"  dsl_builder.build(): FAIL — {type(exc).__name__}: {exc}")
            failures += 1
    else:
        print("  dsl_builder.build(): skipped (no dsl_builder_module in manifest)")

    print("✓ smoke clean" if not failures else f"✗ {failures} issue(s)")
    return 1 if failures else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("activity_dir", help="path to activities/<id>")
    args = ap.parse_args()
    activity_dir = Path(args.activity_dir).resolve()
    if not (activity_dir / "manifest.json").exists():
        print(f"error: no manifest.json in {activity_dir}", file=sys.stderr)
        return 2
    return _smoke(activity_dir)


if __name__ == "__main__":
    raise SystemExit(main())

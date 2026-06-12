#!/usr/bin/env python3
"""Guard: the plugin's authored schemas stay in sync with the runtime models.

The activity-builder package ships ``schemas/card-template.schema.json`` as the
authoring contract external developers (who don't have the platform repo)
validate against. That contract is only trustworthy if it provably matches the
runtime's ``app.models`` pydantic models — otherwise it drifts (exactly the
"schema says X, runtime enforces Y" class the v0.2.5 feedback flagged).

This MAINTAINER tool runs where ``app.models`` is importable (the platform repo
/ CI / pre-commit) and asserts that all three faces of each contract agree —
the pydantic model (runtime truth), the authoring schema external devs validate
against, and the verifier whitelist that gates ship:

  * card block/item models ↔ card-template.schema.json $defs (properties,
    required, ``Literal`` enums, closed objects),
  * ActivityManifest / ActivityRuntimeConfig fields ↔ manifest.schema.json /
    runtime.schema.json properties,
  * ActivityManifest fields / capabilities ``Literal`` / ActivityRuntimeConfig
    fields ↔ the verifier's ALLOWED_MANIFEST_FIELDS / ALLOWED_CAPABILITIES /
    ALLOWED_RUNTIME_FIELDS constants (the guard that catches a stale whitelist
    silently rejecting a newly-supported field — e.g. read_document /
    sandbox_env).

Non-zero exit on any mismatch; the message names the field so the fix is
mechanical. A bundle-version reminder (``schemas/README.md`` vs plugin.json) is
printed but non-blocking.

External developers never run this — they consume the already-synced schemas.

Usage:
    python tools/check_schema_sync.py            # from the package dir
    python tools/check_schema_sync.py --repo /path/to/FreeDeepAgents
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import typing
from pathlib import Path

# Model class name -> $def name in card-template.schema.json (identical here,
# kept explicit so a rename on either side is a visible edit, not a silent skip).
_MODELS = [
    "MarkdownBlock",
    "InfoBlock",
    "InfoItem",
    "FormBlock",
    "FormField",
    "ActionBlock",
    "ActionItem",
    "ImageBlock",
    "ImageItem",
    "AudioBlock",
    "AudioItem",
]

_LEGACY_MANIFEST_FIELDS = {"activity_id"}


def _find_repo_root(override: str | None) -> Path:
    if override:
        return Path(override).resolve()
    try:
        out = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
        return Path(out)
    except Exception:  # noqa: BLE001
        # Fall back to walking up from this file (…/packages/<pkg>/tools/this.py).
        return Path(__file__).resolve().parents[3]


def _model_facts(cls) -> dict:
    """Extract (properties, required, enums) from a pydantic model class."""
    props: set[str] = set()
    required: set[str] = set()
    enums: dict[str, list] = {}
    for fname, field in cls.model_fields.items():
        props.add(fname)
        if field.is_required():
            required.add(fname)
        ann = field.annotation
        if typing.get_origin(ann) is typing.Literal:
            enums[fname] = list(typing.get_args(ann))
    return {"properties": props, "required": required, "enums": enums}


def _schema_facts(defn: dict) -> dict:
    """Extract the same shape from a card-template.schema.json $def."""
    props = set((defn.get("properties") or {}).keys())
    required = set(defn.get("required") or [])
    enums: dict[str, list] = {}
    for pname, pschema in (defn.get("properties") or {}).items():
        if not isinstance(pschema, dict):
            continue
        if "const" in pschema:
            enums[pname] = [pschema["const"]]
        elif "enum" in pschema:
            enums[pname] = list(pschema["enum"])
    return {
        "properties": props,
        "required": required,
        "enums": enums,
        "closed": defn.get("additionalProperties") is False,
    }


def _capabilities_literal(manifest_cls) -> list[str]:
    """Extract the ``Literal[...]`` member of ``list[Literal[...]]`` capabilities."""
    ann = manifest_cls.model_fields["capabilities"].annotation
    inner = typing.get_args(ann)  # (Literal[...],) for list[Literal[...]]
    if inner and typing.get_origin(inner[0]) is typing.Literal:
        return list(typing.get_args(inner[0]))
    return []


def _set_diff(
    label: str, model_side: set[str], other_side: set[str], *, model_name: str, other_name: str
) -> str | None:
    """Return a problem string if the two name sets differ, else None."""
    if model_side == other_side:
        return None
    only_model = sorted(model_side - other_side)
    only_other = sorted(other_side - model_side)
    return f"{label} drift — only in {model_name}: {only_model}; only in {other_name}: {only_other}"


def _schema_props(pkg_dir: Path, name: str) -> set[str]:
    data = json.loads((pkg_dir / "schemas" / name).read_text(encoding="utf-8"))
    return set((data.get("properties") or {}).keys())


def _schema_capabilities_enum(pkg_dir: Path) -> set[str]:
    data = json.loads((pkg_dir / "schemas" / "manifest.schema.json").read_text(encoding="utf-8"))
    items = (data.get("properties", {}).get("capabilities", {}) or {}).get("items", {})
    return set(items.get("enum") or [])


def _plugin_version(pkg_dir: Path) -> str | None:
    try:
        return json.loads((pkg_dir / ".claude-plugin" / "plugin.json").read_text())["version"]
    except Exception:  # noqa: BLE001
        return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--repo", help="FreeDeepAgents repo root (default: git toplevel)")
    args = ap.parse_args()

    repo = _find_repo_root(args.repo)
    if str(repo) not in sys.path:
        sys.path.insert(0, str(repo))

    pkg_dir = Path(__file__).resolve().parents[1]
    schema_path = pkg_dir / "schemas" / "card-template.schema.json"
    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"error: cannot read {schema_path}: {exc}", file=sys.stderr)
        return 2
    defs = schema.get("$defs") or {}

    try:
        import app.models as models
    except Exception as exc:  # noqa: BLE001
        print(f"error: cannot import app.models (run from the platform repo): {exc}", file=sys.stderr)
        return 2

    problems: list[str] = []
    for name in _MODELS:
        cls = getattr(models, name, None)
        if cls is None:
            problems.append(f"{name}: present in schema-sync list but missing from app.models")
            continue
        if name not in defs:
            problems.append(f"{name}: app.models has it but card-template.schema.json $defs does not")
            continue
        m = _model_facts(cls)
        s = _schema_facts(defs[name])
        if m["properties"] != s["properties"]:
            only_model = sorted(m["properties"] - s["properties"])
            only_schema = sorted(s["properties"] - m["properties"])
            problems.append(f"{name}.properties drift — only in model: {only_model}; only in schema: {only_schema}")
        if m["required"] != s["required"]:
            problems.append(f"{name}.required drift — model: {sorted(m['required'])}; schema: {sorted(s['required'])}")
        for fld, model_vals in m["enums"].items():
            schema_vals = s["enums"].get(fld)
            if schema_vals is None:
                problems.append(f"{name}.{fld}: model declares Literal {model_vals} but schema has no const/enum")
            elif set(model_vals) != set(schema_vals):
                problems.append(f"{name}.{fld} enum drift — model: {model_vals}; schema: {schema_vals}")
        if not s["closed"]:
            problems.append(f"{name}: schema $def should be closed (additionalProperties:false) to mirror StrictModel")

    # ── manifest / runtime: model ↔ shipped schema ↔ verifier whitelist ──────
    # This is the guard that would have caught the read_document / sandbox_env
    # drift (verifier whitelist lagging the model). All three faces of each
    # contract must agree: the pydantic model (runtime truth), the authoring
    # schema (what external devs validate against), and the verifier constant
    # (the ship gate).
    manifest_fields = set(models.ActivityManifest.model_fields)
    manifest_contract_fields = manifest_fields | _LEGACY_MANIFEST_FIELDS
    runtime_fields = set(models.ActivityRuntimeConfig.model_fields)
    caps_literal = set(_capabilities_literal(models.ActivityManifest))

    try:
        tools_dir = str(Path(__file__).resolve().parent)
        if tools_dir not in sys.path:
            sys.path.insert(0, tools_dir)
        import activity_verifier as av

        verifier_consts = {
            "ALLOWED_MANIFEST_FIELDS": (set(av.ALLOWED_MANIFEST_FIELDS), manifest_contract_fields, "verifier"),
            "ALLOWED_RUNTIME_FIELDS": (set(av.ALLOWED_RUNTIME_FIELDS), runtime_fields, "verifier"),
            "ALLOWED_CAPABILITIES": (set(av.ALLOWED_CAPABILITIES), caps_literal, "verifier"),
        }
        for const_name, (verifier_set, model_set, _) in verifier_consts.items():
            p = _set_diff(
                f"verifier {const_name}", model_set, verifier_set, model_name="app.models", other_name=const_name
            )
            if p:
                problems.append(p)
    except Exception as exc:  # noqa: BLE001
        problems.append(f"could not import the packaged activity_verifier to check its whitelists: {exc}")

    for model_set, schema_name in (
        (manifest_contract_fields, "manifest.schema.json"),
        (runtime_fields, "runtime.schema.json"),
    ):
        p = _set_diff(
            f"{schema_name} properties",
            model_set,
            _schema_props(pkg_dir, schema_name),
            model_name="app.models",
            other_name=schema_name,
        )
        if p:
            problems.append(p)

    p = _set_diff(
        "manifest.schema.json capabilities enum",
        caps_literal,
        _schema_capabilities_enum(pkg_dir),
        model_name="app.models",
        other_name="schema",
    )
    if p:
        problems.append(p)

    if problems:
        print(f"✗ schema sync: {len(problems)} mismatch(es) between app.models and the packaged schemas/verifier\n")
        for p in problems:
            print(f"  - {p}")
        print("\nFix: edit the schema / verifier constant (or app/models.py) so all faces agree.")
        return 1

    # Bundle version reference: a release-time reminder, NOT a blocker — model
    # drift above is the hard guard; the version line just needs bumping when
    # cutting a release, which can lag a mid-development commit.
    plugin_version = _plugin_version(pkg_dir)
    readme_path = pkg_dir / "schemas" / "README.md"
    readme = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""
    if plugin_version and f"Bundle version: {plugin_version}" not in readme:
        print(
            f"⚠ schemas/README.md 'Bundle version' line doesn't match plugin v{plugin_version} "
            "— bump it before releasing (not blocking)."
        )

    print(
        f"✓ schema sync: card-template ({len(_MODELS)} models) + manifest/runtime schemas + verifier "
        f"whitelists all match app.models (plugin v{plugin_version})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

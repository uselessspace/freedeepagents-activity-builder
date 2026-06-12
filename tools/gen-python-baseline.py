#!/usr/bin/env python3
"""Generate the host Python *baseline* — the set of top-level import names an
activity may use WITHOUT declaring them in its own ``requirements.txt``.

Why a closure and not a raw ``pip freeze``: every activity's deps are installed
into the *same* shared venv (see ``app/dev_sync.py`` pip step + ``Dockerfile``).
A raw freeze would therefore contain packages that some *other* activity pulled
in (kuzu, graphiti-core, akshare, ...), and the verifier would then treat those
as "already provided" and stop requiring the activity that actually uses them to
declare them. So the baseline must be the *platform's own* surface only:

    baseline = transitive closure of the root requirements.txt

We walk the installed dependency graph from the root direct deps (honouring the
extras the root requested and evaluating environment markers), then map each
reachable distribution to the top-level import names it exposes.

Run from the FDA repo root with the runtime venv active so the installed
metadata reflects the real platform:

    .venv/bin/python .claude/skills/freedeepagents-activity-builder/tools/gen-python-baseline.py

Output is written to ``references/runtime-python-baseline.txt`` next to this
package. Re-run whenever the root ``requirements.txt`` changes.
"""

from __future__ import annotations

import argparse
import importlib.metadata as im
import sys
from collections import deque
from pathlib import Path

from packaging.markers import default_environment
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name

PKG_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_REQ = "requirements.txt"
DEFAULT_OUT = PKG_ROOT / "references" / "runtime-python-baseline.txt"


def parse_root_requirements(req_path: Path) -> list[Requirement]:
    reqs: list[Requirement] = []
    for raw in req_path.read_text().splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line or line.startswith("-"):
            continue
        try:
            reqs.append(Requirement(line))
        except Exception:  # noqa: BLE001 — skip anything non-PEP508
            continue
    return reqs


def _dist_requires(dist_name: str) -> list[str]:
    try:
        return im.requires(dist_name) or []
    except im.PackageNotFoundError:
        return []


def closure(root_reqs: list[Requirement]) -> set[str]:
    """Canonical distribution names reachable from the root reqs, installed."""
    env = default_environment()
    seen: set[str] = set()
    # queue items: (canonical_dist_name, set_of_extras_requested)
    queue: deque[tuple[str, frozenset[str]]] = deque()
    for r in root_reqs:
        queue.append((canonicalize_name(r.name), frozenset(r.extras)))

    while queue:
        name, extras = queue.popleft()
        key = name
        if key in seen:
            continue
        # Must be actually installed to count as part of the platform surface.
        try:
            im.metadata(name)
        except im.PackageNotFoundError:
            continue
        seen.add(key)

        for dep_str in _dist_requires(name):
            try:
                dep = Requirement(dep_str)
            except Exception:  # noqa: BLE001
                continue
            marker = dep.marker
            if marker is not None:
                # Evaluate against the base env, and against each requested
                # extra. Include the dep if it holds under any of them.
                ok = marker.evaluate({**env, "extra": ""})
                if not ok:
                    ok = any(marker.evaluate({**env, "extra": e}) for e in extras)
                if not ok:
                    continue
            queue.append((canonicalize_name(dep.name), frozenset(dep.extras)))
    return seen


def import_names_for(dist_canonical: set[str]) -> set[str]:
    """Map a set of canonical dist names to their top-level import names."""
    # packages_distributions(): import_name -> [dist display names]
    pd = im.packages_distributions()
    out: set[str] = set()
    for import_name, dists in pd.items():
        if any(canonicalize_name(d) in dist_canonical for d in dists):
            out.add(import_name)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--requirements", default=DEFAULT_REQ, help="path to the root requirements.txt (default: ./requirements.txt)"
    )
    ap.add_argument("--out", default=str(DEFAULT_OUT), help=f"output path (default: {DEFAULT_OUT})")
    args = ap.parse_args()

    req_path = Path(args.requirements)
    if not req_path.exists():
        print(f"error: {req_path} not found — run from the FDA repo root", file=sys.stderr)
        return 1

    root_reqs = parse_root_requirements(req_path)
    dists = closure(root_reqs)
    imports = import_names_for(dists)
    # Keep only real importable top-level names: valid identifiers, not the
    # private/underscore internals and not mypyc-compiled artifact hashes.
    imports = {n for n in imports if n.isidentifier() and not n.startswith("_")}

    py = f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
    header = [
        "# FreeDeepAgents host Python baseline — top-level import names provided",
        "# by the platform itself (transitive closure of the root",
        "# requirements.txt). An activity may import these WITHOUT listing them",
        "# in activities/<id>/requirements.txt.",
        "#",
        "# Anything an activity imports that is NOT here and NOT in the Python",
        "# stdlib MUST be declared in that activity's requirements.txt — the",
        "# activity verifier enforces this.",
        "#",
        "# GENERATED — do not edit by hand. Regenerate after the root",
        "# requirements.txt changes:",
        "#   .venv/bin/python .claude/skills/freedeepagents-activity-builder/tools/gen-python-baseline.py",
        f"# python: {py}   distributions in closure: {len(dists)}   import names: {len(imports)}",
        "",
    ]
    body = "\n".join(sorted(imports, key=str.lower))
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(header) + body + "\n")
    print(f"wrote {out_path} — {len(imports)} import names from {len(dists)} distributions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

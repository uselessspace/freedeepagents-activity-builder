#!/usr/bin/env bash
# Install a packed FreeDeepAgents activity tarball (produced by
# pack-activity.sh) into the current FDA repo checkout.
#
# Run from inside an FDA repo. The repo root is auto-detected via
# `git rev-parse --show-toplevel`, falling back to the current working
# directory.
#
# Usage:
#   bash <package>/tools/install-activity.sh <package.fda.tgz>
#   bash <package>/tools/install-activity.sh <package.fda.tgz> --force
#   bash <package>/tools/install-activity.sh <package.fda.tgz> --skip-prewarm
#   bash <package>/tools/install-activity.sh <package.fda.tgz> --skip-build
#
# Steps:
#   1. Validate the tarball (must contain fda-package.json + activities/<id>/manifest.json)
#   2. Refuse if activities/<id>/ already exists unless --force
#   3. Extract activities/<id>/ (everything, including site/) into the checkout
#   4. Install activities/<id>/requirements.txt into the repo venv via uv
#      (pip fallback), matching app/dev_sync.py; unless --skip-pip
#   5. Pre-warm node_modules cache for the activity via a one-shot
#      `docker run node:20-slim npm install`, persisted to
#      runtime/sandbox_cache/node_modules/<activity_type_id>/
#   6. For Static Preview activities, build site/dist/ if the package did not include it
#   7. Print restart-uvicorn reminder

set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: $0 <package.fda.tgz> [--force] [--skip-prewarm] [--skip-build] [--skip-pip]
  --force          Overwrite existing activities/<id>/
  --skip-prewarm   Skip npm install for the frontend; the activity will
                   fail to start until you re-run this install without
                   the flag (or run setup-runtime.sh <activity_type_id>).
  --skip-build     Don't run npm run build for Static Preview activities.
                   Use only when site/dist/index.html is already present.
  --skip-pip       Don't install the activity's requirements.txt into the repo
                   venv (via uv, pip fallback). Use only when the deps are
                   already installed; the activity will ImportError otherwise.
EOF
  exit 1
}

PACKAGE=""
FORCE=0
SKIP_PREWARM=0
SKIP_BUILD=0
SKIP_PIP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --skip-prewarm) SKIP_PREWARM=1; shift ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --skip-pip) SKIP_PIP=1; shift ;;
    -h|--help) usage ;;
    -*) echo "unknown flag: $1" >&2; usage ;;
    *)
      if [ -z "$PACKAGE" ]; then PACKAGE="$1"; shift
      else echo "unexpected arg: $1" >&2; usage; fi
      ;;
  esac
done

[ -n "$PACKAGE" ] || usage
[ -f "$PACKAGE" ] || { echo "error: package not found: $PACKAGE" >&2; exit 1; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_prewarm-template.sh"

docker_arch_flag() {
  case "$(uname -m)" in
    arm64|aarch64) echo "--platform linux/arm64" ;;
    x86_64|amd64) echo "--platform linux/amd64" ;;
    *) echo "" ;;
  esac
}

build_static_preview() {
  local activity_id="$1"
  local site_dir="$ROOT/activities/$activity_id/site"
  local cache_dir="$ROOT/runtime/sandbox_cache/node_modules/$activity_id"

  if [ -f "$site_dir/dist/index.html" ]; then
    echo "==> Static preview build already present for '$activity_id'"
    return 0
  fi

  [ -f "$site_dir/package.json" ] || {
    echo "error: Static Preview activity '$activity_id' declares dsl_builder_module but has no site/package.json" >&2
    exit 1
  }

  [ -f "$cache_dir/.fda-ok" ] || {
    echo "error: node_modules cache missing for '$activity_id' at $cache_dir" >&2
    echo "hint: rerun without --skip-prewarm, or run setup-runtime.sh $activity_id first" >&2
    exit 1
  }

  command -v docker >/dev/null 2>&1 || { echo "error: docker not found; cannot build Static Preview site" >&2; exit 1; }

  echo "==> Building Static Preview site for '$activity_id'"
  local arch_flag
  arch_flag="$(docker_arch_flag)"

  # If site/package.json uses npm file: deps (e.g. vendored packages/scenex/),
  # mount the whole repo packages/ tree at the same relative path the host
  # uses, so any tooling that re-resolves bare imports during build (vite
  # dev server, esbuild, tsc paths, etc.) still finds them. Activities using
  # file: are by design only installable from a full FDA monorepo checkout
  # — pack-activity.sh does NOT bundle packages/ into .fda.tgz. We validate
  # every file: target up-front so a missing-vendor situation produces a
  # clear message instead of a generic ENOENT from npm or vite.
  local pkg_mount_arg=""
  if grep -q '"file:' "$site_dir/package.json" 2>/dev/null; then
    local missing_targets=""
    while IFS= read -r target; do
      local abs="$site_dir/$target"
      if [ ! -d "$abs" ]; then
        missing_targets="$missing_targets\n  - $target  (resolved to $abs)"
      fi
    done < <(.venv/bin/python -c "
import json
pkg = json.load(open('$site_dir/package.json'))
for section in ('dependencies', 'devDependencies', 'peerDependencies', 'optionalDependencies'):
    for name, spec in (pkg.get(section) or {}).items():
        if isinstance(spec, str) and spec.startswith('file:'):
            print(spec[len('file:'):])
" 2>/dev/null)

    if [ -n "$missing_targets" ]; then
      echo "error: file: dependency target(s) missing for activity '$activity_id':" >&2
      printf "$missing_targets\n" >&2
      echo "" >&2
      echo "This activity is only installable from a full FDA monorepo checkout." >&2
      exit 1
    fi

    pkg_mount_arg="-v $ROOT/packages:/work/packages:ro"
    echo "    detected file: deps — mounting $ROOT/packages → /work/packages (ro)"
  fi

  docker run --rm $arch_flag \
    -v "$site_dir:/work/activities/$activity_id/site:rw" \
    -v "$cache_dir/node_modules:/work/activities/$activity_id/site/node_modules:rw" \
    $pkg_mount_arg \
    -w "/work/activities/$activity_id/site" \
    node:20-slim \
    sh -lc 'set -eux; npm run build'

  [ -f "$site_dir/dist/index.html" ] || {
    echo "error: npm run build finished but $site_dir/dist/index.html is missing" >&2
    exit 1
  }
}

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Extracting package to staging dir"
tar -xzf "$PACKAGE" -C "$WORK_DIR"

META="$WORK_DIR/fda-package.json"
[ -f "$META" ] || { echo "error: package missing fda-package.json (not a valid .fda.tgz)" >&2; exit 1; }

read -r ACTIVITY_ID HAS_FRONTEND <<EOF
$(.venv/bin/python -c "
import json
m = json.load(open('$META'))
print(m.get('activity_type_id') or m['activity_id'], 'yes' if m.get('has_frontend') else 'no')
")
EOF

echo "    activity:  $ACTIVITY_ID"
[ "$HAS_FRONTEND" = "yes" ] && echo "    frontend:  activities/$ACTIVITY_ID/site" || echo "    frontend:  (none)"

ACT_DST="$ROOT/activities/$ACTIVITY_ID"

if [ -d "$ACT_DST" ] && [ "$FORCE" != 1 ]; then
  echo "error: activities/$ACTIVITY_ID already exists. Use --force to overwrite." >&2
  exit 1
fi

MANIFEST="$WORK_DIR/activities/$ACTIVITY_ID/manifest.json"
[ -f "$MANIFEST" ] || { echo "error: missing manifest.json in package" >&2; exit 1; }
.venv/bin/python -c "import json; json.load(open('$MANIFEST'))" || { echo "error: manifest.json is not valid JSON" >&2; exit 1; }

read -r IS_STATIC_PREVIEW <<EOF
$(.venv/bin/python -c "
import json
m = json.load(open('$MANIFEST'))
print('yes' if m.get('dsl_builder_module') else 'no')
")
EOF

[ "$IS_STATIC_PREVIEW" = "yes" ] && echo "    preview:   Static Preview (will ensure site/dist)" || echo "    preview:   Card-only"

echo "==> Installing activities/$ACTIVITY_ID (including site/ if present)"
rm -rf "$ACT_DST"
mkdir -p "$(dirname "$ACT_DST")"
cp -R "$WORK_DIR/activities/$ACTIVITY_ID" "$ACT_DST"

# Install the activity's Python deps into the repo venv (parity with the
# /dev/sync upload path and the Dockerfile, which install each activity's
# requirements.txt). The runtime shares one venv across activities, so without
# this the activity ImportErrors at runtime on a fresh checkout.
#
# Matches app/dev_sync.py::_py_install_cmd: install via `uv pip install -p
# <interpreter>` (the runtime venv has no pip module, so uv is the primary
# path), falling back to `python -m pip` with a warning only when uv is absent.
if [ -f "$ACT_DST/requirements.txt" ] && [ "$SKIP_PIP" != 1 ]; then
  VENV_PY="$ROOT/.venv/bin/python"
  [ -x "$VENV_PY" ] || VENV_PY="$(command -v python3 || command -v python || true)"
  UV="$(command -v uv || true)"
  [ -n "$UV" ] || { [ -x "$HOME/.local/bin/uv" ] && UV="$HOME/.local/bin/uv"; }
  if [ -n "$VENV_PY" ]; then
    echo "==> Installing Python deps for '$ACTIVITY_ID' (requirements.txt)"
    if [ -n "$UV" ]; then
      install_cmd=("$UV" pip install -p "$VENV_PY" -r "$ACT_DST/requirements.txt")
    else
      echo "warning: uv not found on PATH or ~/.local/bin; falling back to pip" >&2
      install_cmd=("$VENV_PY" -m pip install -r "$ACT_DST/requirements.txt")
    fi
    if ! "${install_cmd[@]}"; then
      echo "warning: dependency install failed for '$ACTIVITY_ID'; the activity" >&2
      echo "         will ImportError until its requirements.txt deps are installed." >&2
    fi
  else
    echo "warning: no python interpreter found; skipping dep install for" >&2
    echo "         '$ACTIVITY_ID'. Install $ACT_DST/requirements.txt manually." >&2
  fi
fi

if [ "$HAS_FRONTEND" = "yes" ] && [ "$SKIP_PREWARM" != 1 ]; then
  echo "==> Pre-warming node_modules cache for '$ACTIVITY_ID'"
  prewarm_template "$ACTIVITY_ID" --force
fi

if [ "$IS_STATIC_PREVIEW" = "yes" ]; then
  if [ "$SKIP_BUILD" = 1 ]; then
    [ -f "$ACT_DST/site/dist/index.html" ] || {
      echo "error: --skip-build was set, but $ACT_DST/site/dist/index.html is missing" >&2
      exit 1
    }
  else
    build_static_preview "$ACTIVITY_ID"
  fi
fi

echo ""
echo "✓ Activity '$ACTIVITY_ID' installed."
echo ""
echo "Next steps:"
echo "  1. Restart uvicorn so it loads the new activity:"
echo "       pkill -f 'uvicorn app.main:app' || true"
echo "       nohup .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 > /tmp/uvicorn.log 2>&1 &"
echo "  2. Open the activity in your client."
if [ "$IS_STATIC_PREVIEW" = "yes" ]; then
  echo "     Static Preview assets are built under activities/$ACTIVITY_ID/site/dist/."
fi

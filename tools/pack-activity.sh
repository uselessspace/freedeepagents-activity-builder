#!/usr/bin/env bash
# Package a FreeDeepAgents activity into a single .fda.tgz tarball that can
# be shipped to another machine and installed via install-activity.sh.
#
# Run from inside an FDA repo (where activities/<id>/ lives). The repo root
# is auto-detected via `git rev-parse --show-toplevel`, falling back to
# the current working directory.
#
# Usage:
#   bash <package>/tools/pack-activity.sh <activity_type_id> [--out <dir>]
#
# What it packs:
#   - activities/<activity_type_id>/        everything under the activity dir
#                                           (manifest, schemas, AGENTS.md,
#                                            card_templates, skills, AND the
#                                            site/ frontend if present)
#
# What it excludes:
#   node_modules, dist, .DS_Store, .git, .env*, *.log, build artifacts.
#   node_modules are re-installed and Static Preview dist/ is rebuilt on the
#   receiving host via install-activity.sh.

set -euo pipefail

usage() {
  echo "Usage: $0 <activity_type_id> [--out <dir>]" >&2
  echo "  --out <dir>   Output directory (default: dist/)" >&2
  exit 1
}

ACTIVITY_ID=""
OUT_DIR="dist"
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT_DIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "unknown flag: $1" >&2; usage ;;
    *)
      if [ -z "$ACTIVITY_ID" ]; then
        ACTIVITY_ID="$1"; shift
      else
        echo "unexpected positional arg: $1" >&2; usage
      fi
      ;;
  esac
done

[ -n "$ACTIVITY_ID" ] || usage

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ACTIVITY_DIR="$ROOT/activities/$ACTIVITY_ID"
MANIFEST="$ACTIVITY_DIR/manifest.json"

[ -d "$ACTIVITY_DIR" ] || { echo "error: activity dir not found: $ACTIVITY_DIR" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "error: manifest.json not found: $MANIFEST" >&2; exit 1; }

mkdir -p "$ROOT/$OUT_DIR"
TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
OUT_TGZ="$ROOT/$OUT_DIR/${ACTIVITY_ID}-${TIMESTAMP}.fda.tgz"

EXCLUDES=(
  --exclude='node_modules'
  --exclude='dist'
  --exclude='.DS_Store'
  --exclude='.git'
  --exclude='.env'
  --exclude='.env.*'
  --exclude='*.log'
  --exclude='__pycache__'
  --exclude='*.pyc'
  --exclude='.vite'
  --exclude='.cache'
  --exclude='.turbo'
  --exclude='coverage'
)

# Build tar contents list — everything lives under activities/<id>/
ITEMS=("activities/$ACTIVITY_ID")
if [ -d "$ACTIVITY_DIR/site" ]; then
  HAS_FRONTEND=1
else
  HAS_FRONTEND=0
fi

# Write package metadata so install-activity.sh can validate
META_TMP="$(mktemp)"
trap 'rm -f "$META_TMP"' EXIT
cat > "$META_TMP" <<JSON
{
  "package_version": 3,
  "activity_type_id": "$ACTIVITY_ID",
  "has_frontend": $( [ "$HAS_FRONTEND" = 1 ] && echo true || echo false ),
  "packed_at": "$TIMESTAMP",
  "items": $(printf '%s\n' "${ITEMS[@]}" | .venv/bin/python -c "import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))" 2>/dev/null || printf '"see-items"')
}
JSON

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"; rm -f "$META_TMP"' EXIT
cp "$META_TMP" "$WORK_DIR/fda-package.json"

echo "==> Packing $ACTIVITY_ID"
echo "    activity:  activities/$ACTIVITY_ID"
[ "$HAS_FRONTEND" = 1 ] && echo "    frontend:  activities/$ACTIVITY_ID/site" || echo "    frontend:  (none)"
echo "    output:    $OUT_TGZ"

(
  cd "$ROOT"
  tar -czf "$OUT_TGZ" \
    "${EXCLUDES[@]}" \
    -C "$WORK_DIR" fda-package.json \
    -C "$ROOT" "${ITEMS[@]}"
)

SIZE="$(du -h "$OUT_TGZ" | cut -f1)"
echo "==> Done. $SIZE → $OUT_TGZ"
echo ""
echo "Ship $OUT_TGZ to the receiving host and run:"
echo "    bash <package>/tools/install-activity.sh $(basename "$OUT_TGZ")"

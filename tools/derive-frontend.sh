#!/usr/bin/env bash
# derive-frontend.sh <activity-id> [--name "<English Short Name>"] [--title "<Browser Title>"] [--accent "#hex"]
#
# Derives a new frontend project at <repo>/activities/<activity-id>/site/
# from <builder-root>/frontend-base/. Idempotent in the sense that it refuses to
# overwrite an existing target.
#
# - <builder-root> is the directory containing this script's parent (auto-detected).
# - <repo> is the git root if inside a git repo, else the current dir.
# - The activity's backend skeleton (activities/<id>/) must already exist
#   (run tools/scaffold-backend.sh first).

set -euo pipefail

usage() {
  cat <<EOF
usage: bash $0 <activity-id> [--name "<Short Name>"] [--title "<Browser Title>"] [--accent "#hex"]

  <activity-id>   kebab-case id, must match ^[a-z][a-z0-9-]{1,30}$
  --name          English short name (default: capitalized id)
  --title         <title> for index.html (default: "<name> — DeepAgents")
  --accent        primary accent color hex (default: #7c4dff)

example:
  bash $0 weather-buddy --name "Weather Buddy" --accent "#06b6d4"
EOF
  exit 1
}

[ "$#" -lt 1 ] && usage
ACTIVITY_ID="$1"; shift

if ! [[ "$ACTIVITY_ID" =~ ^[a-z][a-z0-9-]{1,30}$ ]]; then
  echo "ERROR: activity-id must match ^[a-z][a-z0-9-]{1,30}$"
  echo "got: $ACTIVITY_ID"
  exit 1
fi
if [ "$ACTIVITY_ID" = "_base" ]; then
  echo "ERROR: '_base' is reserved"
  exit 1
fi

default_name() {
  echo "$1" | awk -F- '{ for (i=1; i<=NF; i++) printf "%s%s", toupper(substr($i,1,1)) substr($i,2), (i<NF ? " " : "\n") }'
}
ACTIVITY_NAME="$(default_name "$ACTIVITY_ID")"
ACTIVITY_TITLE=""
ACCENT_COLOR="#7c4dff"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --name)   ACTIVITY_NAME="$2"; shift 2;;
    --title)  ACTIVITY_TITLE="$2"; shift 2;;
    --accent) ACCENT_COLOR="$2"; shift 2;;
    *) echo "unknown arg: $1"; usage;;
  esac
done

[ -z "$ACTIVITY_TITLE" ] && ACTIVITY_TITLE="${ACTIVITY_NAME} — DeepAgents"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

BASE_DIR="$PACKAGE_ROOT/frontend-base"
ACTIVITY_DIR="$REPO_ROOT/activities/$ACTIVITY_ID"
TARGET_DIR="$ACTIVITY_DIR/site"

[ -d "$BASE_DIR" ] || { echo "ERROR: frontend-base not found at $BASE_DIR"; exit 1; }
[ -d "$ACTIVITY_DIR" ] || { echo "ERROR: activity backend not found at $ACTIVITY_DIR — run tools/scaffold-backend.sh $ACTIVITY_ID first"; exit 1; }
[ -e "$TARGET_DIR" ] && { echo "ERROR: $TARGET_DIR already exists. Remove it first if you really want to re-derive."; exit 1; }

echo "[derive] copying frontend-base/ → activities/$ACTIVITY_ID/site/"
cp -R "$BASE_DIR" "$TARGET_DIR"

# Drop frontend-base's developer README; use PROJECT-README.md.tpl instead.
rm -f "$TARGET_DIR/README.md"

echo "[derive] renaming files containing tokens"
find "$TARGET_DIR" -depth -name '*{{ACTIVITY_ID}}*' | while read -r path; do
  newpath="${path//\{\{ACTIVITY_ID\}\}/$ACTIVITY_ID}"
  mv "$path" "$newpath"
done

echo "[derive] dropping .tpl suffix and substituting tokens"
find "$TARGET_DIR" -type f -name '*.tpl' | while read -r tplpath; do
  basename="$(basename "$tplpath")"
  if [ "$basename" = "PROJECT-README.md.tpl" ]; then
    newpath="$(dirname "$tplpath")/README.md"
  else
    newpath="${tplpath%.tpl}"
  fi
  perl -pe "s/\\{\\{ACTIVITY_ID\\}\\}/$ACTIVITY_ID/g; s/\\{\\{ACTIVITY_NAME\\}\\}/$ACTIVITY_NAME/g; s/\\{\\{ACTIVITY_TITLE\\}\\}/$ACTIVITY_TITLE/g; s/\\{\\{ACCENT_COLOR\\}\\}/$ACCENT_COLOR/g" "$tplpath" > "$newpath"
  rm "$tplpath"
done

echo "[derive] verifying no unsubstituted tokens remain"
LEAK_FILES=$(grep -RIlE --exclude-dir=node_modules '\{\{(ACTIVITY_ID|ACTIVITY_NAME|ACTIVITY_TITLE|ACCENT_COLOR)\}\}' "$TARGET_DIR" 2>/dev/null || true)
if [ -n "$LEAK_FILES" ]; then
  echo "ERROR: token substitution left residue in:"
  echo "$LEAK_FILES"
  exit 1
fi

SHA="$(git -C "$PACKAGE_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
if [ -f "$TARGET_DIR/README.md" ]; then
  {
    echo ""
    echo "---"
    echo "_Derived from freedeepagents-activity-builder/frontend-base/ at git $SHA on $(date -u +%Y-%m-%dT%H:%M:%SZ)._"
  } >> "$TARGET_DIR/README.md"
fi

echo "[derive] done. Files:"
( cd "$REPO_ROOT" && find "activities/$ACTIVITY_ID/site" -type f | sort )

cat <<EOF

──── Next steps ────

  1) Author your domain:
       activities/$ACTIVITY_ID/data.schema.json
       activities/$ACTIVITY_ID/dsl_builder.py
       activities/$ACTIVITY_ID/tools.py              ← optional Agent tools
       activities/$ACTIVITY_ID/site/src/lib/types.ts
       activities/$ACTIVITY_ID/site/src/lib/api-client.ts
       activities/$ACTIVITY_ID/site/src/components/
       activities/$ACTIVITY_ID/site/vite.config.ts   ← keep base: './'

  2) Platform-repo/install-side only — prepare the runtime cache:
       bash $PACKAGE_ROOT/tools/setup-runtime.sh $ACTIVITY_ID

     This populates runtime/sandbox_cache/node_modules/$ACTIVITY_ID/.
     (For purely-local dev outside the runtime, you may still run
      "cd activities/$ACTIVITY_ID/site && npm install"; host node_modules is
      not used by the runtime.)

  3) Build:
       cd activities/$ACTIVITY_ID/site && npm run build

  4) Ensure activities/$ACTIVITY_ID/manifest.json has:
       "dsl_builder_module": "dsl_builder"
     Add "tools_module": "tools" only if this activity defines in-process tools.

  5) Resolve or create $REPO_ROOT/.venv using:
       $PACKAGE_ROOT/references/python-environment.md

  6) Verify with that environment:
       <project-python> $PACKAGE_ROOT/tools/activity_verifier.py $REPO_ROOT

EOF

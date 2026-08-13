#!/usr/bin/env bash
# branch-activity.sh <source-id> <new-id> [new-display-name]
#
# Branches an existing activity into a new one.
#
# - <builder-root> is the directory containing this script's parent (auto-detected).
# - <repo> is the git root if inside a git repo, else the current dir.

set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "usage: bash $0 <source-id> <new-id> [new-display-name]"
  echo "example: bash $0 turtle-soup-xy riddle-soup '谜语汤'"
  exit 1
fi

SOURCE_ID="$1"
NEW_ID="$2"
NEW_NAME="${3:-}"

if ! [[ "$NEW_ID" =~ ^[a-z][a-z0-9-]{1,30}$ ]]; then
  echo "ERROR: new-id must match ^[a-z][a-z0-9-]{1,30}$"
  exit 1
fi
[ "$SOURCE_ID" = "$NEW_ID" ] && { echo "ERROR: source and new id must differ"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

SOURCE_DIR="$REPO_ROOT/activities/$SOURCE_ID"
TARGET_DIR="$REPO_ROOT/activities/$NEW_ID"

[ -d "$SOURCE_DIR" ] || { echo "ERROR: source $SOURCE_DIR not found"; exit 1; }
[ -e "$TARGET_DIR" ] && { echo "ERROR: $TARGET_DIR already exists"; exit 1; }

echo "[branch] copying activities/$SOURCE_ID/ → activities/$NEW_ID/"
cp -R "$SOURCE_DIR" "$TARGET_DIR"

if [ -x "$REPO_ROOT/.venv/bin/python" ]; then
  PROJECT_PYTHON="$REPO_ROOT/.venv/bin/python"
elif [ -x "$REPO_ROOT/.venv/Scripts/python.exe" ]; then
  PROJECT_PYTHON="$REPO_ROOT/.venv/Scripts/python.exe"
elif command -v python3 >/dev/null 2>&1; then
  PROJECT_PYTHON="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
  PROJECT_PYTHON="$(command -v python)"
else
  echo "ERROR: no Python interpreter found; create $REPO_ROOT/.venv first." >&2
  echo "See $PACKAGE_ROOT/references/python-environment.md" >&2
  exit 2
fi

SOURCE_NAME=$("$PROJECT_PYTHON" -c "import json,sys; print(json.load(open(sys.argv[1]))['name'])" "$SOURCE_DIR/manifest.json")
echo "[branch] source display name: $SOURCE_NAME"

echo "[branch] substituting in file contents"
find "$TARGET_DIR" -type f \( -name '*.json' -o -name '*.md' -o -name '*.py' \) -print0 \
  | xargs -0 perl -i -pe "s/\Q$SOURCE_ID\E/$NEW_ID/g"

if [ -n "$NEW_NAME" ]; then
  echo "[branch] substituting display name '$SOURCE_NAME' → '$NEW_NAME'"
  find "$TARGET_DIR" -type f \( -name '*.json' -o -name '*.md' \) -print0 \
    | xargs -0 perl -i -pe "s/\Q$SOURCE_NAME\E/$NEW_NAME/g"
fi

echo "[branch] renaming paths containing source-id"
find "$TARGET_DIR" -depth -name "*$SOURCE_ID*" | while read -r path; do
  newpath="${path//$SOURCE_ID/$NEW_ID}"
  mv "$path" "$newpath"
done

HAS_SITE="no"
[ -d "$TARGET_DIR/site" ] && HAS_SITE="yes"

echo "[branch] done. Files:"
( cd "$REPO_ROOT" && find "activities/$NEW_ID" -type f | sort )

cat <<EOF

──── Next steps ────

  1) Open and review:
       activities/$NEW_ID/manifest.json   ← edit description so it differs
       activities/$NEW_ID/AGENTS.md
       activities/$NEW_ID/skills/$NEW_ID-host/SKILL.md

  2) Customize the activity logic — the source's "$SOURCE_NAME" semantics
     have been left in place; rewrite host skill workflows to match the
     new activity's intent.

  3) Update card_templates content (file names already renamed; replace
     literal $SOURCE_NAME references in vars / blocks).
EOF

if [ "$HAS_SITE" = "yes" ]; then
cat <<EOF

  4) Frontend activity — review or re-derive a fresh Static Preview project:
       bash $PACKAGE_ROOT/tools/derive-frontend.sh $NEW_ID --name "<English Short>"
EOF
fi

cat <<EOF

  5) Resolve or create $REPO_ROOT/.venv using:
       $PACKAGE_ROOT/references/python-environment.md

  6) Verify with that environment:
       <project-python> $PACKAGE_ROOT/tools/activity_verifier.py $REPO_ROOT

     Do not pipe through grep: a filter can hide errors from this activity or
     from shared runtime files. Verifier exit 0 is required, then complete
     semantic review and the offline testkit before marking development-ready.

EOF

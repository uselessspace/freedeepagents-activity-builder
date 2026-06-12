#!/usr/bin/env bash
# scaffold-backend.sh <activity-id> [display-name]
#
# Copies <package>/templates/activity-template/ → <repo>/activities/<id>/
# and substitutes "template-activity" → <id> in file content and paths.
# Optionally substitutes "模板活动" → <display-name>.
#
# - <package> is the directory containing this script's parent (auto-detected).
# - <repo> is the git root if inside a git repo, else the current dir.

set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: bash $0 <activity-id> [display-name]"
  echo "example: bash $0 weather-buddy 天气搭子"
  exit 1
fi

ACTIVITY_ID="$1"
DISPLAY_NAME="${2:-$ACTIVITY_ID}"

if ! [[ "$ACTIVITY_ID" =~ ^[a-z][a-z0-9-]{1,30}$ ]]; then
  echo "ERROR: activity-id must match ^[a-z][a-z0-9-]{1,30}$"
  echo "got: $ACTIVITY_ID"
  exit 1
fi
if [ "$ACTIVITY_ID" = "template-activity" ]; then
  echo "ERROR: 'template-activity' is the source name; pick a different id."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

TEMPLATE_DIR="$PACKAGE_ROOT/templates/activity-template"
TARGET_DIR="$REPO_ROOT/activities/$ACTIVITY_ID"

if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "ERROR: template not found at $TEMPLATE_DIR"
  echo "Is this script inside a freedeepagents-activity-builder package?"
  exit 1
fi
if [ -e "$TARGET_DIR" ]; then
  echo "ERROR: $TARGET_DIR already exists. Pick a different id or remove it first."
  exit 1
fi

mkdir -p "$REPO_ROOT/activities"
echo "[scaffold] copying template → activities/$ACTIVITY_ID/"
cp -R "$TEMPLATE_DIR" "$TARGET_DIR"

echo "[scaffold] rewriting file contents"
find "$TARGET_DIR" -type f \( -name '*.json' -o -name '*.md' \) -print0 \
  | xargs -0 perl -i -pe "s/template-activity/$ACTIVITY_ID/g; s/模板活动/$DISPLAY_NAME/g"

echo "[scaffold] renaming paths"
find "$TARGET_DIR" -depth -name '*template-activity*' | while read -r path; do
  newpath="${path//template-activity/$ACTIVITY_ID}"
  mv "$path" "$newpath"
done

echo "[scaffold] done. Files:"
( cd "$REPO_ROOT" && find "activities/$ACTIVITY_ID" -type f | sort )

cat <<EOF

Next steps (in order):
  1) Open and finish authoring:
       activities/$ACTIVITY_ID/manifest.json
       activities/$ACTIVITY_ID/data.schema.json   (typed-KV business data shape — properties + default + x-auto-inject)
       activities/$ACTIVITY_ID/AGENTS.md
       activities/$ACTIVITY_ID/skills/$ACTIVITY_ID-host/SKILL.md
  2) Static Preview only — add dsl_builder_module/tools_module fields
     (see $PACKAGE_ROOT/workflows/02-author-backend.md Step 3)
  3) If your Python code imports any third-party package, declare it (pinned,
     ==) in activities/$ACTIVITY_ID/requirements.txt — the scaffold ships an
     all-comment starter. Don't declare stdlib / platform-baseline / app.*
     (see $PACKAGE_ROOT/references/python-dependencies.md).
  4) Run verifier (Python >= 3.10, no platform repo needed):
       python $PACKAGE_ROOT/tools/activity_verifier.py
  5) Run the offline testkit smoke (no platform repo needed):
       python $PACKAGE_ROOT/testkit/fda_testkit.py activities/$ACTIVITY_ID
EOF

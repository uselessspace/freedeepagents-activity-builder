#!/usr/bin/env bash
# setup-runtime.sh — one-shot "make the runtime ready" for FreeDeepAgents.
#
# Audience: FDA runtime operators (people running the FDA service that will
# host activities). Plugin users who only build & pack activities for shipping
# don't need this — they call pack-activity.sh and ship the .fda.tgz. The
# receiver who installs the .fda.tgz into a running FDA service is the one
# who runs this script.
#
# Prerequisites: an FDA repo checkout containing Dockerfile.sandbox at its
# root. Run from inside that repo.
#
# Idempotent. Safe to re-run after any of:
#   - cloning the repo for the first time
#   - dropping a new activities/<id>/ in via bash <package>/tools/install-activity.sh
#   - editing activities/<id>/site/package.json
#
# What it does (skips work that's already done):
#   1. Build the freedeepagents-sandbox-node:latest image if missing OR if
#      Dockerfile.sandbox is newer than the image's CreatedAt.
#   2. For every frontend activity (activities/<id>/site/package.json exists):
#      - Pre-warm runtime/sandbox_cache/node_modules/<id>/ if no .fda-ok
#        OR if site/package.json is newer than .fda-ok mtime.
#   3. Print a "ready" summary listing every activity and its readiness.
#
# Usage:
#   bash <package>/tools/setup-runtime.sh                # auto-detect & only do what's needed
#   bash <package>/tools/setup-runtime.sh --force        # rebuild image + force-prewarm all caches
#   bash <package>/tools/setup-runtime.sh <activity_type_id>  # only check/prep this activity (+ shared image)
#
# Exit code:
#   0 — runtime is ready (every prepared step succeeded)
#   1 — at least one preparation step failed (image build or prewarm)

set -euo pipefail

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 1
}

FORCE=0
TARGET_ACTIVITY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    -h|--help) usage ;;
    -*) echo "unknown flag: $1" >&2; usage ;;
    *)
      if [ -z "$TARGET_ACTIVITY" ]; then TARGET_ACTIVITY="$1"; shift
      else echo "unexpected arg: $1" >&2; usage; fi
      ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

IMAGE="freedeepagents-sandbox-node:latest"
DOCKERFILE="Dockerfile.sandbox"

[ -f "$DOCKERFILE" ] || { echo "✗ $DOCKERFILE not found at repo root ($REPO_ROOT)" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "✗ docker CLI not in PATH" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "✗ docker daemon not running" >&2; exit 1; }

echo "==> Step 1/2: sandbox image ($IMAGE)"

needs_image_build=0
image_age=""
if [ "$FORCE" = 1 ]; then
  needs_image_build=1
  image_age="(--force)"
elif ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  needs_image_build=1
  image_age="(missing)"
else
  # Compare Dockerfile mtime vs image CreatedAt
  if [ "$(uname)" = "Darwin" ]; then
    dockerfile_mtime=$(stat -f %m "$DOCKERFILE")
  else
    dockerfile_mtime=$(stat -c %Y "$DOCKERFILE")
  fi
  image_created_iso=$(docker image inspect "$IMAGE" --format '{{.Created}}')
  # ISO-8601 → epoch (python is most portable here)
  image_created_epoch=$(.venv/bin/python -c "import datetime as d; print(int(d.datetime.fromisoformat('$image_created_iso'.replace('Z','+00:00')).timestamp()))" 2>/dev/null || echo 0)
  if [ "$dockerfile_mtime" -gt "$image_created_epoch" ]; then
    needs_image_build=1
    image_age="(Dockerfile.sandbox newer than image)"
  fi
fi

if [ "$needs_image_build" = 1 ]; then
  echo "    rebuilding $image_age"
  docker build -f "$DOCKERFILE" -t "$IMAGE" . >/tmp/fda-image-build.log 2>&1 || {
    echo "✗ docker build failed; see /tmp/fda-image-build.log" >&2
    tail -20 /tmp/fda-image-build.log >&2
    exit 1
  }
  echo "    ✓ built"
else
  echo "    ✓ up to date"
fi

echo ""
echo "==> Step 2/2: per-activity node_modules cache"

source "$REPO_ROOT/scripts/_prewarm-template.sh"

# Collect target activities
if [ -n "$TARGET_ACTIVITY" ]; then
  ACTIVITY_DIRS=("$REPO_ROOT/activities/$TARGET_ACTIVITY")
else
  ACTIVITY_DIRS=("$REPO_ROOT/activities"/*/)
fi

declare -a READY_LIST=()
declare -a SKIP_LIST=()
declare -a FAIL_LIST=()

for activity_dir in "${ACTIVITY_DIRS[@]}"; do
  activity_dir="${activity_dir%/}"
  [ -d "$activity_dir" ] || continue
  aid="$(basename "$activity_dir")"
  site_pkg="$activity_dir/site/package.json"
  cache="$REPO_ROOT/runtime/sandbox_cache/node_modules/$aid"

  if [ ! -f "$site_pkg" ]; then
    SKIP_LIST+=("$aid (Card-only — no site/)")
    continue
  fi

  needs_warm=0
  reason=""
  if [ "$FORCE" = 1 ]; then
    needs_warm=1; reason="(--force)"
  elif [ ! -f "$cache/.fda-ok" ]; then
    needs_warm=1; reason="(cache missing)"
  else
    if [ "$(uname)" = "Darwin" ]; then
      pkg_mtime=$(stat -f %m "$site_pkg")
      ok_mtime=$(stat -f %m "$cache/.fda-ok")
    else
      pkg_mtime=$(stat -c %Y "$site_pkg")
      ok_mtime=$(stat -c %Y "$cache/.fda-ok")
    fi
    if [ "$pkg_mtime" -gt "$ok_mtime" ]; then
      needs_warm=1; reason="(package.json newer than cache)"
    fi
  fi

  if [ "$needs_warm" = 1 ]; then
    echo "    $aid: prewarming $reason"
    if prewarm_template "$aid" --force >/tmp/fda-prewarm-$aid.log 2>&1; then
      READY_LIST+=("$aid (rewarmed)")
    else
      FAIL_LIST+=("$aid")
      echo "    ✗ $aid prewarm failed; see /tmp/fda-prewarm-$aid.log" >&2
      tail -10 /tmp/fda-prewarm-$aid.log >&2
    fi
  else
    READY_LIST+=("$aid (cache up to date)")
  fi
done

echo ""
echo "==> Summary"
[ ${#READY_LIST[@]} -gt 0 ] && { echo "  ready:"; printf '    ✓ %s\n' "${READY_LIST[@]}"; }
[ ${#SKIP_LIST[@]} -gt 0 ] && { echo "  skipped:"; printf '    – %s\n' "${SKIP_LIST[@]}"; }
[ ${#FAIL_LIST[@]} -gt 0 ] && { echo "  failed:"; printf '    ✗ %s\n' "${FAIL_LIST[@]}"; }

if [ ${#FAIL_LIST[@]} -gt 0 ]; then
  echo ""
  echo "✗ Runtime is NOT ready — fix the failing activities above and re-run." >&2
  exit 1
fi

echo ""
echo "✓ Runtime ready. Start uvicorn:"
echo "    .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000"

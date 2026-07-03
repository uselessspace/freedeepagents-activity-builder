#!/usr/bin/env bash
# Internal helper: pre-warm node_modules cache for one Static Preview
# activity's site/. Sourced by install-activity.sh (in this same tools/
# directory) and the repo-side scripts/prewarm-templates.sh.
#
# Usage:
#   source scripts/_prewarm-template.sh
#   prewarm_template <activity_type_id> [--force]
#
# Reads:
#   $ROOT      project root (defaults to dirname of this script /..)
# Source dir:
#   $ROOT/activities/<activity_type_id>/site/
# Writes to:
#   $ROOT/runtime/sandbox_cache/node_modules/<activity_type_id>/
#   with .fda-ok sentinel when complete.

prewarm_template() {
  local tpl="$1"
  local force="${2:-}"
  if [ -z "$tpl" ]; then
    echo "prewarm_template: missing activity_id" >&2
    return 2
  fi

  local root="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  local tpl_src="$root/activities/$tpl/site"
  local cache="$root/runtime/sandbox_cache/node_modules/$tpl"

  if [ ! -d "$tpl_src" ]; then
    echo "prewarm[$tpl]: source not found at $tpl_src" >&2
    return 1
  fi
  if [ ! -f "$tpl_src/package.json" ]; then
    echo "prewarm[$tpl]: $tpl_src has no package.json — not a Vite/Node activity, skipping" >&2
    return 0
  fi

  if [ -f "$cache/.fda-ok" ] && [ "$force" != "--force" ]; then
    echo "prewarm[$tpl]: cache already warm at $cache (use --force to redo)"
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    echo "prewarm[$tpl]: docker not found — cannot pre-warm" >&2
    return 1
  fi

  mkdir -p "$cache"
  rm -rf "$cache"/* "$cache"/.[!.]* 2>/dev/null || true

  local arch_flag=""
  case "$(uname -m)" in
    arm64|aarch64) arch_flag="--platform linux/arm64" ;;
    x86_64|amd64)  arch_flag="--platform linux/amd64" ;;
  esac

  # npm file: dependencies must be self-contained under the activity site
  # (enforced by activity_verifier.py). When present, use --install-links so
  # the warm cache receives copied packages rather than symlinks back into the
  # temporary build tree.
  local use_install_links=0
  if grep -q '"file:' "$tpl_src/package.json" 2>/dev/null; then
    use_install_links=1
  fi

  echo "prewarm[$tpl]: running npm install in node:20-slim ($(uname -m)) → $cache"
  docker run --rm $arch_flag \
    -v "$tpl_src:/src:ro" \
    -v "$cache:/out:rw" \
    -e FDA_ACTIVITY_ID="$tpl" \
    -e FDA_USE_INSTALL_LINKS="$use_install_links" \
    node:20-slim \
    sh -lc '
      set -eux
      mkdir -p /work/activities/$FDA_ACTIVITY_ID/site
      cp -a /src/. /work/activities/$FDA_ACTIVITY_ID/site/
      cd /work/activities/$FDA_ACTIVITY_ID/site
      rm -rf node_modules dist

      # --install-links forces `file:` deps to be copied into node_modules
      # rather than symlinked. Needed so the warm cache is portable across
      # docker runs (a symlink into a ro bind-mount disappears on unmount).
      install_flags="--no-audit --no-fund"
      if [ "$FDA_USE_INSTALL_LINKS" = 1 ]; then
        install_flags="$install_flags --install-links"
      fi
      npm install $install_flags

      # Stage packages under a literal `node_modules/` subdir so Node ESM
      # can resolve bare imports via ancestor walking (it looks for
      # "<ancestor>/node_modules/<pkg>", and the cache mounted at /cache/...
      # must have a true `node_modules` ancestor for that walk to succeed).
      # Manifests must symlink site/node_modules -> $CACHE/node_modules.
      mkdir -p /out/node_modules
      cp -a node_modules/. /out/node_modules/
      touch /out/.fda-ok
    '

  if [ ! -f "$cache/.fda-ok" ]; then
    echo "prewarm[$tpl]: failed (no .fda-ok marker)" >&2
    return 1
  fi
  local size
  size="$(du -sh "$cache" 2>/dev/null | cut -f1)"
  echo "prewarm[$tpl]: ok ($size)"
}

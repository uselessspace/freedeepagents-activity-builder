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

  # Detect npm file: dependencies that point outside site/ (e.g. activities
  # using vendored monorepo packages like packages/scenex/). When present,
  # mount the whole packages/ tree into the container at the same relative
  # path the host uses, so `file:../../../packages/foo` resolves correctly
  # during `npm install`. Activities that don't use file: deps incur no
  # overhead.
  #
  # An activity with file: deps is by design only installable from the FDA
  # monorepo (pack-activity.sh does NOT bundle packages/ into .fda.tgz).
  # If $root/packages doesn't contain every referenced target, fail fast
  # with a clear message so a missing-vendor situation is obvious rather
  # than surfacing as a generic npm ENOENT.
  local needs_packages_mount=0
  if grep -q '"file:' "$tpl_src/package.json" 2>/dev/null; then
    needs_packages_mount=1
  fi

  local pkg_mount_arg=""
  if [ "$needs_packages_mount" = 1 ]; then
    # Resolve every file: dep relative to $tpl_src and check it exists
    # under $root/packages. site is always at activities/<id>/site/, so
    # file:../../../packages/foo → $root/packages/foo. We sed out the
    # ../../../ prefix anchored to the activity layout; anything else
    # we can't auto-validate, just leave it to npm.
    local missing_targets=""
    while IFS= read -r target; do
      # target is the raw file: URL value, e.g. ../../../packages/scenex/engine
      local abs="$tpl_src/$target"
      if [ ! -d "$abs" ]; then
        missing_targets="$missing_targets\n  - $target  (resolved to $abs)"
      fi
    done < <(.venv/bin/python -c "
import json, sys
pkg = json.load(open('$tpl_src/package.json'))
for section in ('dependencies', 'devDependencies', 'peerDependencies', 'optionalDependencies'):
    for name, spec in (pkg.get(section) or {}).items():
        if isinstance(spec, str) and spec.startswith('file:'):
            print(spec[len('file:'):])
" 2>/dev/null)

    if [ -n "$missing_targets" ]; then
      echo "prewarm[$tpl]: ❌ file: dependency target(s) missing:" >&2
      printf "$missing_targets\n" >&2
      echo "" >&2
      echo "This activity is only installable from a full FDA monorepo checkout." >&2
      echo "If you received it as a standalone .fda.tgz, ask the author to send" >&2
      echo "the matching packages/ tree (or re-vendor it into the activity)." >&2
      return 1
    fi

    pkg_mount_arg="-v $root/packages:/work/packages:ro"
    echo "prewarm[$tpl]: detected file: deps — mounting $root/packages → /work/packages (ro)"
  fi

  echo "prewarm[$tpl]: running npm install in node:20-slim ($(uname -m)) → $cache"
  docker run --rm $arch_flag \
    -v "$tpl_src:/src:ro" \
    $pkg_mount_arg \
    -v "$cache:/out:rw" \
    -e FDA_ACTIVITY_ID="$tpl" \
    -e FDA_USE_INSTALL_LINKS="$needs_packages_mount" \
    node:20-slim \
    sh -lc '
      set -eux
      # Mirror the host repo layout inside the container so relative `file:`
      # paths in site/package.json resolve to /work/packages/<pkg> exactly as
      # they would on the host. /work/packages is a bind-mount when
      # needs_packages_mount=1; otherwise it does not exist, which is fine
      # for activities without file: deps.
      mkdir -p /work/activities/$FDA_ACTIVITY_ID/site
      cp /src/package.json /work/activities/$FDA_ACTIVITY_ID/site/
      if [ -f /src/package-lock.json ]; then
        cp /src/package-lock.json /work/activities/$FDA_ACTIVITY_ID/site/
      fi
      cd /work/activities/$FDA_ACTIVITY_ID/site

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

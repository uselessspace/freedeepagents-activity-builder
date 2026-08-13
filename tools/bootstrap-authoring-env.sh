#!/usr/bin/env bash
set -euo pipefail

PYTHON_VERSION="3.12.13"
PYTHON_RELEASE="20260807"
NODE_VERSION="20.20.2"
PYTHON_MIRROR="${FDA_PYTHON_MIRROR:-https://registry.npmmirror.com/-/binary/python-build-standalone}"
NODE_MIRROR="${FDA_NODE_MIRROR:-https://registry.npmmirror.com/-/binary/node}"
PIP_INDEX="${FDA_PIP_INDEX:-https://pypi.tuna.tsinghua.edu.cn/simple}"
NPM_REGISTRY="${FDA_NPM_REGISTRY:-https://registry.npmmirror.com}"
PROJECT_ROOT="$PWD"
WITH_NODE=0
export PIP_INDEX_URL="$PIP_INDEX"
export npm_config_registry="$NPM_REGISTRY"

usage() {
  cat <<'EOF'
Usage: bootstrap-authoring-env.sh [--project-root PATH] [--with-node]

Create/reuse <project-root>/.venv for FDA Activity Builder authoring. Add
--with-node only for a Static Preview activity (site/package.json exists).

Downloads, when needed, go to <project-root>/.fda-tools and use configurable
domestic mirrors. Override them with FDA_PYTHON_MIRROR, FDA_NODE_MIRROR,
FDA_PIP_INDEX, or FDA_NPM_REGISTRY.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-root)
      [ "$#" -ge 2 ] || { echo "ERROR: --project-root needs a path" >&2; exit 2; }
      PROJECT_ROOT=$2
      shift 2
      ;;
    --with-node)
      WITH_NODE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[ -d "$PROJECT_ROOT" ] || { echo "ERROR: project root does not exist: $PROJECT_ROOT" >&2; exit 1; }
PROJECT_ROOT=$(CDPATH= cd -- "$PROJECT_ROOT" && pwd -P)
TOOLS_DIR="$PROJECT_ROOT/.fda-tools"
VENV_DIR="$PROJECT_ROOT/.venv"
mkdir -p "$TOOLS_DIR"

append_gitignore() {
  entry=$1
  ignore_file="$PROJECT_ROOT/.gitignore"
  if ! [ -f "$ignore_file" ] || ! grep -Fqx "$entry" "$ignore_file"; then
    if [ -s "$ignore_file" ] && [ "$(tail -c 1 "$ignore_file" | wc -l | tr -d ' ')" = "0" ]; then
      printf '\n' >> "$ignore_file"
    fi
    printf '%s\n' "$entry" >> "$ignore_file"
  fi
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "ERROR: sha256sum or shasum is required" >&2
    return 1
  fi
}

download_and_verify() {
  base=$1
  version_dir=$2
  filename=$3
  destination=$4
  sums="$5/SHA256SUMS"

  command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required for runtime download" >&2; return 1; }
  echo "Downloading $filename"
  curl --fail --location --silent --show-error --retry 3 --connect-timeout 20 \
    "$base/$version_dir/$filename" --output "$destination"
  curl --fail --location --silent --show-error --retry 3 --connect-timeout 20 \
    "$base/$version_dir/SHASUMS256.txt" --output "$sums" 2>/dev/null || \
  curl --fail --location --silent --show-error --retry 3 --connect-timeout 20 \
    "$base/$version_dir/SHA256SUMS" --output "$sums"

  expected=$(awk -v name="$filename" '$2 == name || $2 == "*" name { print $1; exit }' "$sums")
  [ -n "$expected" ] || { echo "ERROR: checksum entry missing for $filename" >&2; return 1; }
  actual=$(sha256_file "$destination")
  [ "$actual" = "$expected" ] || { echo "ERROR: checksum mismatch for $filename" >&2; return 1; }
}

python_minor() {
  "$1" -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")' 2>/dev/null
}

project_python=""
venv_python="$VENV_DIR/bin/python"
if [ -e "$VENV_DIR" ]; then
  [ -x "$venv_python" ] || {
    echo "ERROR: $VENV_DIR exists but has no executable bin/python; refusing to overwrite it" >&2
    exit 1
  }
  detected=$(python_minor "$venv_python" || true)
  [ "$detected" = "3.12" ] || {
    echo "ERROR: existing .venv uses Python ${detected:-unknown}; FDA authoring requires 3.12" >&2
    exit 1
  }
  project_python=$venv_python
  echo "Reusing Python: $project_python"
else
  base_python=""
  for candidate in python3.12 python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && [ "$(python_minor "$(command -v "$candidate")" || true)" = "3.12" ]; then
      base_python=$(command -v "$candidate")
      break
    fi
  done

  if [ -z "$base_python" ]; then
    os=$(uname -s)
    arch=$(uname -m)
    case "$os:$arch" in
      Darwin:arm64|Darwin:aarch64) target="aarch64-apple-darwin" ;;
      Darwin:x86_64) target="x86_64-apple-darwin" ;;
      Linux:aarch64|Linux:arm64) target="aarch64-unknown-linux-gnu" ;;
      Linux:x86_64|Linux:amd64) target="x86_64-unknown-linux-gnu" ;;
      *) echo "ERROR: unsupported platform for automatic Python install: $os $arch" >&2; exit 1 ;;
    esac
    if [ "$os" = "Linux" ] && { [ -e /etc/alpine-release ] || ldd --version 2>&1 | grep -qi musl; }; then
      target=${target%-gnu}-musl
    fi

    python_home="$TOOLS_DIR/python-$PYTHON_VERSION"
    managed_python="$python_home/bin/python3"
    if [ -x "$managed_python" ] && [ "$(python_minor "$managed_python" || true)" = "3.12" ]; then
      base_python="$managed_python"
      echo "Reusing managed Python: $base_python"
    elif [ -e "$python_home" ]; then
      echo "ERROR: incomplete or incompatible managed Python path already exists: $python_home" >&2
      exit 1
    else
      temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/fda-authoring.XXXXXX")
      staging=$(mktemp -d "$TOOLS_DIR/.python-staging.XXXXXX")
      trap 'rm -rf -- "$temp_dir" "$staging"' EXIT
      archive="cpython-$PYTHON_VERSION+$PYTHON_RELEASE-$target-install_only_stripped.tar.gz"
      download_and_verify "$PYTHON_MIRROR" "$PYTHON_RELEASE" "$archive" "$temp_dir/$archive" "$temp_dir"
      tar -xzf "$temp_dir/$archive" -C "$staging" --strip-components=1
      base_python="$staging/bin/python3"
      [ -x "$base_python" ] || { echo "ERROR: downloaded Python archive has an unexpected layout" >&2; exit 1; }
      [ "$(python_minor "$base_python")" = "3.12" ] || { echo "ERROR: downloaded Python failed its version check" >&2; exit 1; }
      mv "$staging" "$python_home"
      base_python="$python_home/bin/python3"
      rm -rf -- "$temp_dir"
      trap - EXIT
      echo "Installed project-local Python: $base_python"
    fi
  fi

  "$base_python" -m venv "$VENV_DIR"
  project_python=$venv_python
  echo "Created project environment: $VENV_DIR"
fi

cat > "$VENV_DIR/pip.conf" <<EOF
[global]
index-url = $PIP_INDEX
timeout = 60
EOF

local_node_bin=""
node_path=$(command -v node 2>/dev/null || true)
npm_path=$(command -v npm 2>/dev/null || true)
node_major=""
npm_major=""
if [ -n "$node_path" ]; then
  node_major=$("$node_path" -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)
fi
if [ -n "$npm_path" ]; then
  npm_major=$("$npm_path" --version 2>/dev/null | awk -F. 'NR == 1 { print $1 }')
fi

if [ "$WITH_NODE" -eq 1 ]; then
  if { [ "$node_major" = "20" ] || [ "$node_major" = "22" ]; } && [ "$npm_major" = "10" ]; then
    echo "Reusing Node: $node_path ($("$node_path" --version)), npm $($npm_path --version)"
  else
    os=$(uname -s)
    arch=$(uname -m)
    case "$os:$arch" in
      Darwin:arm64|Darwin:aarch64) node_target="darwin-arm64" ;;
      Darwin:x86_64) node_target="darwin-x64" ;;
      Linux:aarch64|Linux:arm64) node_target="linux-arm64" ;;
      Linux:x86_64|Linux:amd64) node_target="linux-x64" ;;
      *) echo "ERROR: unsupported platform for automatic Node install: $os $arch" >&2; exit 1 ;;
    esac
    node_home="$TOOLS_DIR/node-v$NODE_VERSION"
    if [ -x "$node_home/bin/node" ]; then
      local_node_bin="$node_home/bin"
      node_action="Reusing managed Node"
    else
      [ ! -e "$node_home" ] || {
        echo "ERROR: incomplete managed Node path already exists: $node_home" >&2
        exit 1
      }
      temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/fda-authoring.XXXXXX")
      staging=$(mktemp -d "$TOOLS_DIR/.node-staging.XXXXXX")
      trap 'rm -rf -- "$temp_dir" "$staging"' EXIT
      archive="node-v$NODE_VERSION-$node_target.tar.gz"
      download_and_verify "$NODE_MIRROR" "v$NODE_VERSION" "$archive" "$temp_dir/$archive" "$temp_dir"
      tar -xzf "$temp_dir/$archive" -C "$staging" --strip-components=1
      [ -x "$staging/bin/node" ] || { echo "ERROR: downloaded Node archive has an unexpected layout" >&2; exit 1; }
      mv "$staging" "$node_home"
      local_node_bin="$node_home/bin"
      node_action="Installed project-local Node"
      rm -rf -- "$temp_dir"
      trap - EXIT
    fi
    PATH="$local_node_bin:$PATH"
    node_major=$("$local_node_bin/node" -p 'process.versions.node.split(".")[0]')
    npm_major=$("$local_node_bin/npm" --version | awk -F. 'NR == 1 { print $1 }')
    [ "$node_major" = "20" ] && [ "$npm_major" = "10" ] || {
      echo "ERROR: managed Node/npm failed its version check" >&2
      exit 1
    }
    echo "$node_action: $local_node_bin/node ($("$local_node_bin/node" --version))"
  fi
fi

append_gitignore ".venv/"
append_gitignore ".fda-tools/"

env_file="$TOOLS_DIR/authoring-env.sh"
cat > "$env_file" <<'EOF'
#!/usr/bin/env bash
FDA_PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export VIRTUAL_ENV="$FDA_PROJECT_ROOT/.venv"
export PATH="$VIRTUAL_ENV/bin:$PATH"
export PIP_INDEX_URL="${FDA_PIP_INDEX:-https://pypi.tuna.tsinghua.edu.cn/simple}"
export npm_config_registry="${FDA_NPM_REGISTRY:-https://registry.npmmirror.com}"
if [ -d "$FDA_PROJECT_ROOT/.fda-tools/node-v20.20.2/bin" ]; then
  export PATH="$FDA_PROJECT_ROOT/.fda-tools/node-v20.20.2/bin:$PATH"
fi
EOF
chmod +x "$env_file"

echo
echo "Authoring environment ready."
echo "Python: $($project_python -c 'import sys; print(sys.executable, sys.version.split()[0])')"
if [ "$WITH_NODE" -eq 1 ]; then
  if [ -n "$local_node_bin" ]; then
    node_path="$local_node_bin/node"
    npm_path="$local_node_bin/npm"
  fi
  echo "Node: $node_path ($($node_path --version)); npm $($npm_path --version)"
fi
echo "Load it in a new shell with: source \"$env_file\""

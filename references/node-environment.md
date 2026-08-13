# Static Preview Node environment

Use this preflight only when the activity has a frontend project at
`activities/<activity_type_id>/site/package.json`.
Card-only activities skip Node setup entirely.

## Supported baseline

- The current FDA runtime builds Static Preview projects in `node:20-slim`.
- Builder 0.4.36 supports Node 20 or 22 with npm 10.x for local authoring.
- Prefer Node 20 for the closest match to the runtime. An existing compatible
  Node 22 environment may be reused; do not downgrade it merely for parity.
- For another target runtime, its Docker image and the activity's
  `package.json.engines` are authoritative.

Node does not use a Python-style project `.venv`. Do not copy a Node binary or
global npm packages into the project. The activity owns only:

- `site/.nvmrc`, which recommends Node 20 to version managers;
- `site/package.json.engines`, which accepts the supported compatibility range;
- `site/package-lock.json`, which pins the dependency graph; and
- `site/node_modules/`, a generated local dependency directory that must stay
  ignored and must not be treated as deliverable source.

`site/dist/` is different: it is verified local build output and may remain in
the development directory as evidence, but FDA source sync excludes generated
`dist/` and rebuilds it server-side. It is not source that must be uploaded.

## Coding Agent decision flow

1. Confirm this is Static Preview. If `site/package.json` does not exist, stop
   this preflight without installing Node.
2. From `site/`, inspect `node --version` and `npm --version` without changing
   the machine. Continue when Node major is 20 or 22 and npm major is 10.
3. Reuse a compatible environment. Record its executable paths and versions.
4. If Node is missing or incompatible and an existing version manager is
   available, use it to install/select Node 20 for this project.
5. If no supported version manager or base Node is available, report the
   detected state and ask the user to install or authorize Node 20 LTS. Do not
   silently run a remote installer, use administrator privileges, alter a
   global Node installation, or select an unbounded `latest` version.
6. Never delete or overwrite an existing lockfile or version-manager config
   without reviewing it. Resolve conflicting project constraints explicitly.

Portable version checks:

```bash
node -e 'const m=Number(process.versions.node.split(".")[0]); if (![20,22].includes(m)) process.exit(1); console.log(process.execPath, process.version)'
npm --version
```

The npm major printed by the second command must be 10. On PowerShell, the same
`node -e` and `npm --version` commands work unchanged.

## Select Node 20 when setup is needed

Use only a version manager that is already installed and understood by the
project. Examples:

```bash
# nvm on macOS/Linux, when already available
nvm install 20
nvm use 20

# fnm on macOS/Linux/Windows, when already available
fnm install 20
fnm use 20
```

Do not use `curl | sh`, `sudo npm`, `npm install -g`, or an OS package-manager
mutation without the user's authorization. Installing a runtime is a visible
machine setup action, not an implicit build step.

## Install and verify dependencies

Run commands from `activities/<activity_type_id>/site/`:

1. If `package-lock.json` exists, run `npm ci` so the checked-in graph wins.
2. On the first derivation, when no lockfile exists, run `npm install` once and
   keep the generated `package-lock.json` in the activity directory.
3. Run `npm run lint`, then `npm run build`.
4. Confirm `dist/index.html` exists. Never use a global package install to make
   a missing dependency appear.

Record the Node and npm executable paths/versions, whether the environment was
reused or selected, the dependency command, lint/build results, and
`site/dist/index.html` in `Development Verification`.

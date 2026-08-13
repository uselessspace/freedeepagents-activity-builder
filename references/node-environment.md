# Static Preview Node environment

Use this preflight only when the activity has a frontend project at
`activities/<activity_type_id>/site/package.json`.
Card-only activities skip Node setup entirely.

## Supported baseline

- The current FDA runtime builds Static Preview projects in `node:20-slim`.
- Builder 0.4.38 supports Node 20 or 22 with npm 10.x for local authoring.
- Prefer Node 20 for the closest match to the runtime. An existing compatible
  Node 22 environment may be reused; do not downgrade it merely for parity.
- For another target runtime, its Docker image and the activity's
  `package.json.engines` are authoritative.

Node does not use a Python-style project `.venv`. A compatible system or
version-manager Node may be reused; otherwise the bundled bootstrap keeps a
pinned runtime under `<project-root>/.fda-tools/`, never in the activity
directory. The activity owns only:

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
4. If Node is missing or incompatible, tell the user the bundled bootstrap will
   download pinned Node 20 from the configured domestic mirror, then run it
   with the explicit Static Preview flag. It installs only under
   `<project-root>/.fda-tools/`, verifies SHA-256, and changes no global runtime.
5. Never select an unbounded `latest` version. Review existing lockfiles and
   version-manager config instead of overwriting them.

Portable version checks:

```bash
node -e 'const m=Number(process.versions.node.split(".")[0]); if (![20,22].includes(m)) process.exit(1); console.log(process.execPath, process.version)'
npm --version
```

The npm major printed by the second command must be 10. On PowerShell, the same
`node -e` and `npm --version` commands work unchanged.

## Recommended bootstrap for Static Preview

The same bootstrap creates/reuses Python first and adds Node only when explicitly
requested. It pins Node 20.20.2 + npm 10, downloads from npmmirror, verifies the
published checksum, and configures npm to use npmmirror. Card-only activities
must omit the Node flag.

macOS / Linux:

```bash
bash <builder-root>/tools/bootstrap-authoring-env.sh \
  --project-root <project-root> \
  --with-node
```

Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<builder-root>\tools\bootstrap-authoring-env.ps1" -ProjectRoot "<project-root>" -WithNode
```

Replace placeholders with actual absolute paths. The scripts write a project
environment loader under `.fda-tools/`; source it before later `npm` commands
when a local Node was installed. Override `FDA_NODE_MIRROR` and
`FDA_NPM_REGISTRY` to use an enterprise mirror. No overseas source is a default
fallback, and the scripts never use `curl | sh`, `sudo`, global npm installs,
or an OS package-manager mutation.
The Windows `Bypass` is limited to that child process; it changes no persistent
execution-policy scope and cannot override enforced organization Group Policy.

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

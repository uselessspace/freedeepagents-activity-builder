# Workflow 04: Derive the Static Preview frontend

Skip for Card-only activities. Start from the `## Frontend Decision` block from
`skills/activity-frontend/SKILL.md`; if it is missing, write it before deriving.

## Step 0: resolve the frontend runtime

Follow [`../references/node-environment.md`](../references/node-environment.md)
before deriving or building. Reuse Node 20 or 22 with npm 10; prefer Node 20 to
mirror the current `node:20-slim` runtime. If no compatible Node exists, tell
the user the next command installs pinned, checksum-verified Node from the
configured domestic mirror into the project, then run:

```bash
bash <builder-root>/tools/bootstrap-authoring-env.sh \
  --project-root <project-root> \
  --with-node
```

Use `bootstrap-authoring-env.ps1 -ProjectRoot <project-root> -WithNode` on
Windows. The script changes no global runtime and has no overseas-source
fallback.

## Step 1: derive

```bash
bash <builder-root>/tools/derive-frontend.sh <activity-id> --name "<English Short Name>" --accent "#7c4dff"
```

The script:
1. Validates id matches `^[a-z][a-z0-9-]{1,30}$`
2. `cp -r <builder-root>/frontend-base/` → `activities/<id>/site/`
3. Drops `<builder-root>/frontend-base/README.md` (developer-only doc); promotes `PROJECT-README.md.tpl` to `README.md`
4. For every `*.tpl` file: substitutes `{{ACTIVITY_ID}}`, `{{ACTIVITY_NAME}}`, `{{ACTIVITY_TITLE}}`, `{{ACCENT_COLOR}}`, then drops the `.tpl` suffix
5. Renames any file/dir whose name contains `{{ACTIVITY_ID}}` to the resolved id
6. Verifies no token residue remains
7. Stamps the source git SHA into the README

## Step 2: pick a reference archetype

The `frontend-base/` ships a Vite scaffold. For the current runtime model, the frontend is a static SPA served under `/preview/<activity_type_id>/<instance_id>/` and calls only the current preview root's `api/...` endpoints.

UI 形态不限——dashboard、graph、canvas、game、timeline、scenes 都是被验证可行的方向。SPA 的硬约束是**契约**：消费当前 preview root 的 `api/dsl.json`（形状由自己的 `dsl_builder.py` 定义），不直连 runtime 内部状态。DSL 形状随 UI 设计走，先画 UI 再定 DSL。

## Step 3: define the DSL boundary

The frontend is driven by the dict returned from `activities/<id>/dsl_builder.py`.

Required backend/frontend alignment:

- `data.schema.json` declares the durable typed-KV business fields.
- `tools.py` exposes user-semantic mutations when the UI needs interactions.
- `dsl_builder.py` reads `data.json` and artifacts, then returns the `AppDsl`
  shape.
- `src/lib/types.ts` mirrors that `AppDsl` shape.
- `src/lib/api-client.ts` fetches `/api/dsl.json` and subscribes to
  `/api/dsl/stream` when `refresh_model` needs live updates.
- When `navigation_axis` is `agent-to-preview`, `useDsl()` also exposes the
  latest named `preview_navigate` event as `navigation`; validate its private
  fields before selecting an activity-private route, view, or business object.
  Do not encode browser clicks, focus, scrolling, or DOM targets.

Do not make the SPA read activity-private state from generic runtime APIs.

## Step 4: implement domain code

In `activities/<id>/site/`, edit activity-owned files. The final app should:

- set Vite `base: './'`
- use the frontend base `apiUrl()` / preview-mount helpers instead of manually parsing or hardcoding user/dev preview paths
- fetch `dsl.json` from `apiUrl('/dsl.json')` when using `dsl_builder_module`
- subscribe to `apiUrl('/dsl/stream')` when live updates are needed
- reuse that same EventSource for `preview_navigate`; never open a navigation-only stream
- avoid dev-server-only `/api/*` plugin routes in production code
- let end-users upload their own images / voice recordings (and persist them) via `POST api/upload` — see [user-upload.md](../references/user-upload.md)
- for a recording that the Agent must process, pass that same-instance upload's `resource_ref` in the Preview Agent Turn `attachment_refs`; it becomes the current-turn `file_0` — see [preview-agent-turns.md](../references/preview-agent-turns.md)
- for an immediate editable transcript without an Agent turn, declare `asr` and send multipart `audio` with `Idempotency-Key` to `POST api/asr` — see [preview-asr.md](../references/preview-asr.md)
- keep the complete `resource_ref` with business records and reclaim only zero-reference resources after discard/replace/delete — see [asset-lifecycle.md](../references/asset-lifecycle.md)

Typical files:

| File | Purpose |
|---|---|
| `src/lib/types.ts` | Your domain TypeScript types (replace placeholder `AppState`) |
| `src/lib/api-client.ts` | REST methods wrapping `request<T>()` from `lib/http.ts` |
| `src/components/...` | Activity UI components |
| `src/hooks/...` | Activity-specific hooks (base ships only the runtime-wired `useDsl`) |
| `src/App.tsx` | Replace `<DomainView/>` with the real UI |
| `vite.config.ts` | Keep `base: './'`; Vite's native build output remains `dist/` |
| `package.json` | Include build script; dependencies must install in Linux Docker |

The runtime serves `site/dist/`. Local `npm run dev` uses `src/lib/mock-dsl.ts`
as a fallback only; production data must come from `dsl_builder.py`.

Agent navigation is also runtime-only in local Vite dev. Unit-test how a sample
payload changes semantic route/view/object selection, then verify real delivery
through an installed preview. Full contract:
[preview-navigation.md](../references/preview-navigation.md).

## Step 5: smoke build (local host loop — fast)

```bash
cd activities/<id>/site
node --version     # Node 20 or 22
npm --version      # npm 10.x
if [ -f package-lock.json ]; then npm ci; else npm install; fi
npm run lint       # tsc --noEmit, must be 0 errors
npm run build      # vite build, must succeed
npm run dev        # optional authoring preview only
```

The conditional chooses exactly one dependency command: `npm ci` when
`package-lock.json` exists, otherwise `npm install` once. Keep the generated
lockfile. Never overwrite a user lockfile or use a global install to bypass a
missing dependency.

These run on the **host** and use `activities/<id>/site/node_modules/` on the host disk. They're for fast iteration while authoring. Runtime installation uses a Linux Docker cache and runs `npm run build` again if `site/dist/index.html` is missing.

Any failure → check error → fix one thing → re-run. See [../policies/fix-loop.md](../policies/fix-loop.md).

Capture screenshots at mobile and desktop widths for any visual or layout-heavy
activity. Fix text overflow, missing images, blank canvases, and overlapping UI
before directory handoff or sync.

## Step 6: choose the runtime validation path

For the default FDA Dev Client workflow, keep the project under
`activities/<id>/` and use `fda-dev --folder activities/<id>`. Static Preview
activities are rebuilt during `sync` / `message --sync-first`; no hand-built
archive or local install step is required.

If developing against a local FDA platform repo instead, prepare its Linux
runtime cache after authoring or any `package.json` bump:

```bash
bash <builder-root>/tools/setup-runtime.sh <id>
```

It's idempotent and pre-warms `runtime/sandbox_cache/node_modules/<id>/` if
`site/package.json` is newer than the cache's `.fda-ok` sentinel (or the cache
doesn't exist yet).

The cache exists because the host may be macOS/arm64 while runtime build uses Linux. Native binaries (rollup, esbuild, ...) differ — sharing the host's `node_modules/` can crash the build.

> **Whenever you edit `site/package.json`, re-run `setup-runtime.sh <id>`**
> before smoke-testing a local runtime. Force a clean cache rebuild with
> `--force`. Shared FDA Dev Client development uses `fda-dev` sync instead.

## Step 7: confirm manifest + build output

Re-open `activities/<id>/manifest.json` and confirm:

- `dsl_builder_module` is set to `"dsl_builder"`
- `tools_module` is set only when `tools.py` exists and exports `make_tools(ctx)`
- `site/dist/index.html` exists after `npm run build`
- `vite.config.ts` uses `base: './'`
- when enabled, `preview_navigate` moves the intended view, duplicate events are
  idempotent, and a second user on the same instance receives no event

[02-author-backend.md](02-author-backend.md) Step 3 has the canonical manifest fields.

## Hand-off

If user wants UI polish:
```
Frontend derived for <id>. Engaging optional frontend polish workflow.
Proceeding to 05-frontend-polish.md, then directory verification in 06-verify-directory.md.
```

Otherwise:
```
Frontend derived for <id>. Static Preview complete.
Proceeding to directory verification in 06-verify-directory.md.
```

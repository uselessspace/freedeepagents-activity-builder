# Workflow 04: Derive the Static Preview frontend

Skip for Card-only activities. Start from the `## Frontend Decision` block from
`skills/activity-frontend/SKILL.md`; if it is missing, write it before deriving.

## Step 1: derive

```bash
bash <package>/tools/derive-frontend.sh <activity-id> --name "<English Short Name>" --accent "#7c4dff"
```

The script:
1. Validates id matches `^[a-z][a-z0-9-]{1,30}$`
2. `cp -r <package>/frontend-base/` → `activities/<id>/site/`
3. Drops `<package>/frontend-base/README.md` (developer-only doc); promotes `PROJECT-README.md.tpl` to `README.md`
4. For every `*.tpl` file: substitutes `{{ACTIVITY_ID}}`, `{{ACTIVITY_NAME}}`, `{{ACTIVITY_TITLE}}`, `{{ACCENT_COLOR}}`, then drops the `.tpl` suffix
5. Renames any file/dir whose name contains `{{ACTIVITY_ID}}` to the resolved id
6. Verifies no token residue remains
7. Stamps the source git SHA into the README

## Step 2: pick a reference archetype

The `frontend-base/` ships a Vite scaffold. For the current runtime model, the frontend must be a static SPA that reads runtime APIs under `/preview/<activity_type_id>/<activity_id>/api/...`.

UI 形态不限——dashboard、graph、canvas、game、timeline、scenes 都是被验证可行的方向。SPA 的唯一硬约束是**契约**：只消费 `/preview/<activity_type_id>/<activity_id>/api/dsl.json` 返回的 DSL（你自己在 `dsl_builder.py` 里定义的形状），不直连 runtime 内部状态。DSL 形状随 UI 设计走，先画 UI 再定 DSL。

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

Do not make the SPA read activity-private state from `frontend-src/` or generic
runtime APIs.

## Step 4: implement domain code

In `activities/<id>/site/`, edit activity-owned files. The final app should:

- set Vite `base: './'`
- parse `activity_id` / `instance_id` from `window.location.pathname`
- fetch `dsl.json` from `/preview/<activity_type_id>/<activity_id>/api/dsl.json` when using `dsl_builder_module`
- subscribe to `/preview/<activity_type_id>/<activity_id>/api/dsl/stream` when live updates are needed
- avoid dev-server-only `/api/*` plugin routes in production code

Typical files:

| File | Purpose |
|---|---|
| `src/lib/types.ts` | Your domain TypeScript types (replace placeholder `AppState`) |
| `src/lib/api-client.ts` | REST methods wrapping `request<T>()` from `lib/http.ts` |
| `src/components/...` | Activity UI components |
| `src/hooks/...` | Activity-specific hooks (base ships `useDsl` and `useApi`) |
| `src/App.tsx` | Replace `<DomainView/>` with the real UI |
| `vite.config.ts` | Set `base: './'`; keep `build.outDir = 'dist'` |
| `package.json` | Include build script; dependencies must install in Linux Docker |

The runtime serves `site/dist/`. Local `npm run dev` uses `src/lib/mock-dsl.ts`
as a fallback only; production data must come from `dsl_builder.py`.

## Step 5: smoke build (local host loop — fast)

```bash
cd activities/<id>/site
npm install        # ~3-30s depending on cache; host-side, NOT the runtime cache
npm run lint       # tsc --noEmit, must be 0 errors
npm run build      # vite build, must succeed
npm run dev        # optional authoring preview only
```

These run on the **host** and use `activities/<id>/site/node_modules/` on the host disk. They're for fast iteration while authoring. Runtime installation uses a Linux Docker cache and runs `npm run build` again if `site/dist/index.html` is missing.

Any failure → check error → fix one thing → re-run. See [../policies/fix-loop.md](../policies/fix-loop.md).

Capture screenshots at mobile and desktop widths for any visual or layout-heavy
activity. Fix text overflow, missing images, blank canvases, and overlapping UI
before packaging.

## Step 6: prepare the runtime cache *(platform-repo / install-side step)*

> **External developers without the platform repo: skip this step.**
> `setup-runtime.sh` needs an FDA repo checkout (Dockerfile.sandbox) + Docker —
> it's run by whoever installs your `.fda.tgz`, not by you. For local UI work,
> `npm run build` in `site/` is enough; record the cache/build line as
> "deferred to maintainer" in Ship Verification.

After authoring or any future `package.json` bump, the installer runs:

```bash
bash <package>/tools/setup-runtime.sh <id>
```

It's idempotent and pre-warms `runtime/sandbox_cache/node_modules/<id>/` if `site/package.json` is newer than the cache's `.fda-ok` sentinel (or the cache doesn't exist yet). Packaged installs run the same cache prewarm and then build `site/dist/` when needed.

The cache exists because the host may be macOS/arm64 while runtime build uses Linux. Native binaries (rollup, esbuild, ...) differ — sharing the host's `node_modules/` can crash the build.

> **Whenever you edit `site/package.json`, re-run `setup-runtime.sh <id>`** before smoke-testing packaged/runtime behavior. Force a clean cache rebuild with `--force`.

Packaged verification must also run `bash <package>/tools/install-activity.sh <pkg>` so the
Linux build path is tested, not only the host `npm run build` path.

## Step 7: confirm manifest + build output

Re-open `activities/<id>/manifest.json` and confirm:

- `dsl_builder_module` is set to `"dsl_builder"`
- `tools_module` is set only when `tools.py` exists and exports `make_tools(ctx)`
- `site/dist/index.html` exists after `npm run build`
- `vite.config.ts` uses `base: './'`

[02-author-backend.md](02-author-backend.md) Step 3 has the canonical manifest fields.

## Hand-off

If user wants UI polish:
```
Frontend derived for <id>. Engaging optional frontend polish workflow.
Proceeding to 05-frontend-polish.md, then 06-verify-and-ship.md.
```

Otherwise:
```
Frontend derived for <id>. Static Preview complete.
Proceeding to 06-verify-and-ship.md.
```

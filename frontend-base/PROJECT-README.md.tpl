# {{ACTIVITY_NAME}}

FreeDeepAgents activity frontend derived from the Activity Builder Static Preview base.

## Develop

Two paths — pick by where you want to run:

**FDA Dev Client / shared runtime**: keep this project under
`activities/{{ACTIVITY_ID}}/` and point `fda-dev --folder` at that directory.
Static Preview sync rebuilds the frontend server-side.

**Local dev outside the runtime** (faster inner loop while authoring):

This project supports Node 20 or 22 with npm 10. A compatible installation may
be reused; otherwise the parent activity project may provide a project-local
Node 20 runtime under `.fda-tools/`. `.nvmrc` remains available to version
managers and does not trigger a global install.

```bash
node --version
npm --version
if [ -f package-lock.json ]; then npm ci; else npm install; fi
npm run dev          # vite at http://localhost:5173, using mock DSL fallback
npm run lint         # tsc --noEmit
npm run build        # production bundle to dist/
```

If this frontend uses npm `file:` dependencies, keep those packages inside this
activity directory (for example `file:vendor/local-widget`). Directory sync only
receives the activity project, so `file:../../../packages/...` and other paths
outside the activity are rejected by the verifier.

When `package.json` changes, `fda-dev sync` / `message --sync-first` rebuilds
Static Preview remotely. When using a local FDA platform repo instead, rerun
`setup-runtime.sh {{ACTIVITY_ID}} --force` from the active Builder bundle.

## What's where

| Path | Purpose |
|---|---|
| `src/lib/types.ts` | Activity domain types |
| `src/lib/api-client.ts` | Static Preview DSL fetch + SSE stream helpers |
| `src/components/` | Activity UI |
| `src/hooks/` | Activity-specific hooks (the base ships `useDsl`) |
| `src/lib/mock-dsl.ts` | Local mock DSL for `npm run dev`; production uses `dsl_builder.py` |

`useDsl()` also returns the latest `navigation` event when the Agent emits a
runtime `preview_navigate` signal. Validate your activity-private fields before
selecting a semantic route, view, or business object. Do not translate it into
browser clicks, focus, scrolling, or DOM targets. It shares the DSL EventSource
and is not available from the local mock server.

## Shared base modules — do not edit

These came from the Builder's `frontend-base/` and are kept in sync across all derived activities:

- `src/lib/{http,api-base,asset-url}.ts`
- `src/hooks/useDsl.ts`
- `src/components/{ErrorBoundary,LoadingSpinner,ApiErrorBanner}.tsx`
- `src/styles/index.css`

If every activity should receive a change, update the Builder's source
`frontend-base/` and re-derive. Activity-specific behavior belongs outside
these shared files.

## Static Preview manifest

For production preview, add `"dsl_builder_module": "dsl_builder"` to `activities/{{ACTIVITY_ID}}/manifest.json` and implement `activities/{{ACTIVITY_ID}}/dsl_builder.py`. Keep `src/lib/types.ts` aligned with that builder's returned DSL. Add `"tools_module": "tools"` only when the activity exposes in-process business tools.

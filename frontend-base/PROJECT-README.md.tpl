# {{ACTIVITY_NAME}}

FreeDeepAgents activity frontend, derived from `<package>/frontend-base/`.

## Develop

Two paths — pick by where you want to run:

**Runtime / packaged install** (the way users actually use this):

```bash
packages/freedeepagents-activity-builder/tools/setup-runtime.sh {{ACTIVITY_ID}}
npm run build  # creates site/dist/
```

**Local dev outside the runtime** (faster inner loop while authoring):

```bash
npm install          # local node_modules; independent of the cache
npm run dev          # vite at http://localhost:5173, using mock DSL fallback
npm run lint         # tsc --noEmit
npm run build        # production bundle to dist/
```

When the host `package.json` changes (you added/removed a dep), re-run
`packages/freedeepagents-activity-builder/tools/setup-runtime.sh {{ACTIVITY_ID}} --force` so packaged/runtime
builds use the new deps.

## What's where

| Path | Purpose |
|---|---|
| `src/lib/types.ts` | Activity domain types |
| `src/lib/api-client.ts` | Static Preview DSL fetch + SSE stream helpers |
| `src/components/` | Activity UI |
| `src/hooks/` | Activity-specific hooks (the base ships `useDsl`) |
| `src/lib/mock-dsl.ts` | Local mock DSL for `npm run dev`; production uses `dsl_builder.py` |

## Shared base modules — do not edit

These came from `<package>/frontend-base/` and are kept in sync across all derived activities:

- `src/lib/{http,api-base,asset-url}.ts`
- `src/hooks/{useApi,useDsl}.ts`
- `src/components/{ErrorBoundary,LoadingSpinner,ApiErrorBanner}.tsx`
- `src/styles/index.css`

If you need to change one of these, change it in `_base/` and re-derive (or cherry-pick the change).

## Static Preview manifest

For production preview, add `"dsl_builder_module": "dsl_builder"` to `activities/{{ACTIVITY_ID}}/manifest.json` and implement `activities/{{ACTIVITY_ID}}/dsl_builder.py`. Keep `src/lib/types.ts` aligned with that builder's returned DSL. Add `"tools_module": "tools"` only when the activity exposes in-process business tools.

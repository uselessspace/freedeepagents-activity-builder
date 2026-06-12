# Policy: never edit shared frontend-base modules

## Rule

In a derived `activities/<id>/site/` project, the following files came from `<package>/frontend-base/` and are kept in sync across all derived activities:

```
src/lib/{http, api-base, asset-url}.ts
src/hooks/{useApi, useDsl}.ts
src/components/{ErrorBoundary, LoadingSpinner, ApiErrorBanner}.tsx
src/styles/index.css
```

**Don't edit these in your derived project.** If you need to:

- **Add a feature only your activity needs** → put it in a NEW file under `src/lib/<your-helper>.ts`, don't extend the shared one
- **Change something that all activities should benefit from** → edit `<package>/frontend-base/<the-file>` and re-derive (or cherry-pick the change into already-derived projects)

## Why

When the next activity author runs `derive-frontend.sh`, they get the canonical `frontend-base/` content. If your fork diverged silently, your customizations are quietly missing in their project — and they don't know.

## Verifier?

Currently no automated check (the verifier focuses on `app/` boundary, not `activities/<id>/site/`). It's an honor system; reviewers should grep `git log --diff-filter=M -- activities/<id>/site/src/lib/http.ts` style during PR review.

## Genuine local diffs are OK

Adding files in `src/components/`, `src/hooks/`, `src/lib/types.ts`,
`src/lib/api-client.ts`, `src/lib/mock-dsl.ts`, or `data/<id>.json` — that's
the **point** of derivation. Just keep the shared base files untouched.

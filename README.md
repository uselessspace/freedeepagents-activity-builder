# freedeepagents-activity-builder

`freedeepagents-activity-builder` is a Codex + Claude plugin for building
FreeDeepAgents intelligent activities. It guides a coding agent from an idea,
through product and runtime classification, into implementation, packaging, and
install verification.

The default deliverable is a `.fda.tgz` package that can be installed into a
FreeDeepAgents repo with `bash <package>/tools/install-activity.sh`.

> **Two placeholders used throughout the docs:** `<package>` = the directory
> where this plugin is installed/unpacked (the one holding this README);
> `<project-root>` / `<repo-root>` = *your* working repo, the directory that
> holds (or will hold) `activities/`. Scaffold and verifier commands run from
> `<project-root>`, not from `<package>`.

## What It Does

- Captures an Activity Brief before scaffolding.
- Classifies the activity into Card-only or Static Preview.
- Separates runtime-provided capabilities from activity-owned tools and
  Static Preview interaction surfaces.
- Keeps activity business logic inside `activities/<activity_type_id>/skills/`.
- Builds card templates, typed-KV data schemas, host skills, and optional
  activity-owned tools.
- Builds Static Preview activities with `site/`, `dsl_builder.py`, optional
  tools/handlers/Preview Actions, and `site/dist/`.
- Wires optional Agent-driven semantic route, view, or business-object
  selection through the user-scoped `preview_navigate` event on the existing
  DSL stream, without browser click/scroll automation.
- Packages the final activity as `.fda.tgz`.
- Verifies install and runtime smoke behavior before calling the activity ready.

## Package Layout

```text
packages/freedeepagents-activity-builder/
|-- SKILL.md                         # router entry
|-- .codex-plugin/plugin.json        # Codex plugin manifest
|-- .claude-plugin/plugin.json       # Claude plugin manifest
|-- skills/
|   |-- activity-orchestrator/SKILL.md
|   |-- activity-brief/SKILL.md
|   |-- activity-classifier/SKILL.md
|   |-- activity-builder/SKILL.md
|   |-- activity-frontend/SKILL.md
|   |-- activity-packager/SKILL.md
|   |-- activity-verify/SKILL.md     # static verify (verifier + strict-tool-schema)
|   |-- activity-review/SKILL.md     # semantic self-audit (logic conflicts; in-session LLM)
|   |-- activity-smoke/SKILL.md      # runtime SSE smoke test
|   |-- activity-diagnostician/SKILL.md  # error-class triage
|   `-- activity-dev-cli/SKILL.md    # safe shared-runtime CLI workflow
|-- workflows/                       # deeper build procedures
|-- policies/                        # runtime and output guardrails
|-- references/                      # lookup tables and examples
|-- examples/                        # end-to-end activity walkthroughs
|-- frontend-base/                   # Vite/React/Tailwind Static Preview base
|-- schemas/                         # JSON schemas mirrored by verifier rules
|-- templates/activity-template/     # backend scaffold
|-- testkit/                         # offline pytest/CLI harness (zero deps, no platform repo)
`-- tools/                           # scaffold, derive, setup, verifier scripts
```

## Workflow Skills

The root `SKILL.md` is the Claude/project-level router. Codex loads
`skills/activity-orchestrator/SKILL.md` from `.codex-plugin`, which routes to
the same stages:

1. `activity-brief` asks who the activity serves, what the core loop is, which
   UI and tool capabilities are needed, and what success looks like.
2. `activity-classifier` writes the fixed Activity Classification:
   `frontend_axis`, `tool_axis`, additive `runtime_capabilities`, `image_axis`,
   `navigation_axis`, `spa_interaction_axis`, `runtime_mode`, and
   `delivery_target` (+ free-form `implementation_notes`).
3. `activity-builder` scaffolds and implements activity-owned files.
4. `activity-frontend` guides Static Preview UI choices without vendoring
   third-party frontend skill source.
5. `activity-review` checks prompt/tool/card semantics and sends any CONFLICT
   back for repair.
6. `activity-packager` creates `.fda.tgz`, runs `bash <package>/tools/install-activity.sh`,
   and captures smoke-test evidence.

Four standalone utility skills support any stage: `activity-verify` (static
verifier + strict-tool-schema check), `activity-smoke` (runtime SSE smoke
test), `activity-diagnostician` (maps errors to fix classes), and
`activity-dev-cli` (safe `doctor` / `status` / sync / pull / real-turn / logs
workflows against a shared dev runtime). The
`testkit/` directory ships the offline harness behind the always-required
testkit smoke line (see `testkit/README.md`).

## Frontend Capability

The plugin includes a lightweight frontend guidance skill instead of copying
external UI skills. It covers Tailwind, motion, lucide, shadcn-style component
patterns, and UI archetypes such as dashboards, games, canvas tools, timelines,
graphs, pet/avatar experiences, and form workflows.

Static Preview activities may also use Agent-driven navigation: successful
activity tools/handlers call `ctx.emit_preview_navigation(...)`, and the SPA
consumes the named `preview_navigate` event from its existing DSL EventSource.
See [references/preview-navigation.md](references/preview-navigation.md).

Optional shadcn MCP examples or local UI skills may be used when available.
They are not required by this package.

## Static Preview ASR

For a recording UI, declare `"asr"` in `manifest.capabilities` and choose one
public path; do not use browser Web Speech as the platform fallback.

| Need | SPA path | Result |
|---|---|---|
| Show/edit a transcript immediately; Agent is optional afterwards | multipart `POST api/asr` with `audio` and `Idempotency-Key` | transcript and billable usage; no Agent turn |
| Let the Agent reason over the recording or decide what to do with its text | `POST api/upload` → Preview Agent Turn `attachment_refs` | copied current-turn `file_0`; Agent calls `transcribe_audio(file_0)` |

The browser never supplies a user ID or ASR provider credential. The preview
gateway supplies the trusted identity used for attribution and billing. See
[references/preview-asr.md](references/preview-asr.md),
[references/preview-agent-turns.md](references/preview-agent-turns.md), and
[references/asr-tools.md](references/asr-tools.md).

## Runtime Boundary

One hard rule: activity-specific behavior (decisions, prompts, state semantics,
domain workflow, third-party abilities) lives in `activities/<id>/` — never in
the generic runtime (`app/`, `schemas/`). Full boundary table
and rationale: [policies/runtime-boundary.md](policies/runtime-boundary.md).

## Install

See [INSTALL.md](INSTALL.md) for Codex plugin installation, Claude plugin
installation, and repo-local symlink fallback.

## Verification Authority

The semantic review, `tools/activity_verifier.py`, offline testkit, and real
installed activity smoke test form the release gate. Documentation summarizes
the intended workflow; contract checks and runnable evidence win.

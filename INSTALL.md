# Install freedeepagents-activity-builder

This package can be used as a Codex plugin, a Claude plugin, or a repo-local
skill symlink. All forms point at the same internal workflow skills.

## Resolve the two roots first

`<builder-root>` always means the directory containing this `INSTALL.md`,
`SKILL.md`, `skills/`, and `tools/`. Do not type the angle-bracket placeholder
literally.

| Checkout layout | `<builder-root>` |
|---|---|
| Standalone [`uselessspace/freedeepagents-activity-builder`](https://github.com/uselessspace/freedeepagents-activity-builder) clone | the cloned repository root |
| FreeDeepAgents monorepo checkout | `<FreeDeepAgents-root>/packages/freedeepagents-activity-builder` |
| Installed Codex/Claude plugin | the installed directory containing the root `SKILL.md` |

`<project-root>` is different: it is the repository where the generated
`activities/` directory lives. Commands below must use the actual root for the
layout you installed; never append `packages/freedeepagents-activity-builder`
to a standalone clone.

## Compatibility preflight

Use one Builder bundle per run. Read its plugin manifest version and do not mix
scripts/templates from a repo checkout with Skills loaded from a different
plugin cache. Builder 0.4.41 targets the current FDA contract based on Python
3.12, DeepAgents 0.7.x, and LangChain Core 1.x. For another target runtime,
its `app/models.py` and pinned requirements are authoritative; run
`tools/check_schema_sync.py` in that runtime or install the Builder release
paired with it. A newer Builder can author fields an older runtime rejects.

### Coding Agent Python-environment preflight

Before running any Builder Python command, resolve a compatible project-local
interpreter. Reuse `<project-root>/.venv` when it matches the target runtime;
if it does not exist, create it in `<project-root>` with Python 3.12 for the
current FDA target. Never create it inside `activities/<activity_type_id>/` or
in a separate installed plugin/cache that is not the project root. If a
writable standalone Builder clone is also the activity project, its root
`.venv` is valid because `<builder-root>` and `<project-root>` are the same.

Do not overwrite an incompatible `.venv`, silently downgrade Python, or install
into the system interpreter. If Python 3.12 itself is unavailable, tell the
user the next command downloads a pinned, checksum-verified runtime from a
domestic mirror, then run the bundled POSIX or PowerShell bootstrap. It installs
only in `<project-root>/.fda-tools/` and `.venv/`. Full cross-platform commands,
mirror overrides, dependency layers, and evidence requirements are in
[`references/python-environment.md`](references/python-environment.md).

### Coding Agent Node-environment preflight (Static Preview only)

Card-only activities do not need Node. When the activity contains
`site/package.json`, check Node before deriving or building: Builder 0.4.41
supports Node 20 or 22 with npm 10, and recommends Node 20 because the current
FDA frontend build runtime uses `node:20-slim`. A compatible existing Node 22
installation is valid and does not need to be downgraded.

If no compatible Node exists, tell the user the bootstrap will download a
pinned Node 20 from a domestic mirror and run it with the Static Preview flag.
The runtime stays under `<project-root>/.fda-tools/`; the script verifies its
published checksum and does not use administrator privileges or change the
global runtime. The activity project pins the preference with `site/.nvmrc`, constrains compatibility through
`site/package.json.engines`, installs dependencies locally in
`site/node_modules/`, and keeps `site/package-lock.json`. Full cross-platform
logic and evidence requirements are in
[`references/node-environment.md`](references/node-environment.md).

Recommended commands after replacing both placeholders with absolute paths:

```bash
# macOS / Linux; omit --with-node for Card-only
bash <builder-root>/tools/bootstrap-authoring-env.sh \
  --project-root <project-root> \
  --with-node
```

```powershell
# Windows PowerShell 5.1+; omit -WithNode for Card-only
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<builder-root>\tools\bootstrap-authoring-env.ps1" -ProjectRoot "<project-root>" -WithNode
```

`-ExecutionPolicy Bypass` applies only to this child PowerShell process; the
command does not persistently change the user's or machine's execution policy.
If organization Group Policy still blocks the script, stop and ask the
administrator instead of changing a broader policy scope.

The defaults use npmmirror for Python/Node distributions, Tsinghua PyPI for
Python packages, and npmmirror for npm packages. They do not silently fall back
to an overseas source. Enterprise mirrors can be supplied through the
`FDA_PYTHON_MIRROR`, `FDA_NODE_MIRROR`, `FDA_PIP_INDEX`, and
`FDA_NPM_REGISTRY` environment variables.

> **Install the whole package, not individual skills.** The skills cross-link
> each other and the shared `policies/` / `references/` / `workflows/` /
> `schemas/` / `testkit/` dirs with package-relative paths (e.g.
> `../../workflows/06-verify-directory.md`). Those resolve only when the full
> package tree is intact. Extracting a single `skills/<one>/` directory into
> `~/.claude/skills/` strands every cross-reference — symlink or copy the
> **entire** `<builder-root>/` directory instead.

## Codex Plugin

The Codex manifest is:

```text
<builder-root>/.codex-plugin/plugin.json
```

Install or register the package with the Codex plugin mechanism used in your
environment. The manifest exposes the internal `skills/` directory and offers
short default prompts such as:

```text
帮我设计并生成一个 FDA 智能活动
Build and verify a FreeDeepAgents activity directory
Classify this activity idea into Card-only or Static Preview
```

After installation, ask Codex to build an FDA activity. The router runs
`activity-brief`, `activity-classifier`, builder, optional frontend, review,
and directory verification.

## Claude Plugin

The Claude manifest is:

```text
<builder-root>/.claude-plugin/plugin.json
```

In Claude Code, install the package root as a local plugin when supported.
For a standalone clone:

```bash
/plugin install /absolute/path/to/freedeepagents-activity-builder
```

On Windows, use the cloned root itself (quotes are recommended when the path
contains spaces):

```text
/plugin install "C:\path\to\freedeepagents-activity-builder"
```

安装后，`skills/` 下每个 SKILL.md 都会被**自动发现**并可用 `/<name>` 直接调用——
plugin.json 的 `skills` 数组只是显式声明 + 排序，不是白名单。可直接调的 skill：

主工作流（按顺序）：

```text
/activity-brief         需求澄清
/activity-classifier    分类定型（card-only / static-preview）
/activity-builder       scaffold + 实现（含 card_templates / form 表单卡）
/activity-frontend      Static Preview 前端（仅需要时）
/activity-verify        开发目录验收（verifier + strict schema + testkit）
```

按需独立工具（随时单独调）：

```text
/activity-review        本地语义自审（CONFLICT 阻断；SMELL / NOTE 可记录取舍）
/activity-smoke         端到端冒烟（核 trace.jsonl 的 card_item / turn_completed / done）
/activity-diagnostician 失败排查（turn_id / 错误日志 / 症状 → 根因 + 修复）
/activity-dev-cli       共享 dev runtime（连通、状态、同步、拉取、真 turn、日志）
```

（`/activity-orchestrator` 是 Codex 侧 router 入口；Claude 用户用根 router
`/freedeepagents-activity-builder` 即可。）

如果已安装 FDA Dev Client，可直接让 Coding Agent 调用：

```text
/activity-dev-cli 检查当前活动能否连上开发服务器，先不要修改任何内容
/activity-dev-cli 预演同步，然后跑一个新的 smoke turn，失败时拉取日志
/activity-dev-cli 比较服务器源码和本地源码，但不要覆盖本地文件
```

该 skill 默认从 `doctor` / `status` / `--dry-run` 开始。实际同步会写开发
服务器；`pull --force` 和 `login --replace-session` 需要用户明确授权。

Restart Claude Code if your version scans plugins only at startup.

## Repo-Local Link Or Copy Fallback

If plugin installation is unavailable, expose the package as a project skill:

### macOS / Linux

```bash
cd /path/to/your-project
mkdir -p .claude/skills
ln -s "/absolute/path/to/freedeepagents-activity-builder" \
  .claude/skills/freedeepagents-activity-builder
```

Or copy the complete Builder root:

```bash
cp -R "/absolute/path/to/freedeepagents-activity-builder" \
  .claude/skills/freedeepagents-activity-builder
```

### Windows PowerShell

A directory junction avoids copying and normally does not require Developer
Mode. Run this from your activity project, not from the Builder clone:

```powershell
Set-Location "C:\path\to\your-project"
New-Item -ItemType Directory -Force ".claude\skills" | Out-Null
New-Item -ItemType Junction `
  -Path ".claude\skills\freedeepagents-activity-builder" `
  -Target "C:\absolute\path\to\freedeepagents-activity-builder"
```

If a junction is unsuitable, copy the complete directory instead:

```powershell
Set-Location "C:\path\to\your-project"
New-Item -ItemType Directory -Force ".claude\skills" | Out-Null
Copy-Item -Recurse `
  "C:\absolute\path\to\freedeepagents-activity-builder" `
  ".claude\skills\freedeepagents-activity-builder"
```

The destination must not already contain a stale partial copy. If you copy
instead of linking, replace that copy after every Builder update.

The link/copy commands above are native PowerShell, and environment bootstrap
has the native `tools/bootstrap-authoring-env.ps1` entry. Other Builder helpers
under `tools/*.sh` still require Git Bash or WSL on Windows; run them from the
activity project's mounted path. The Python verifier and testkit can run
directly in PowerShell through `<project-root>/.venv\Scripts\python.exe`.

## Build And Deliver An Activity Directory

The plugin should guide the coding agent through these stages:

1. Write `## Activity Brief`.
2. Write `## Activity Classification`.
3. Generate or update `activities/<activity_type_id>/`.
4. For Static Preview only, resolve Node and build `site/dist/`.
5. Verify the activity directory:

```bash
<project-python> <builder-root>/tools/activity_verifier.py <project-root>
<project-python> <builder-root>/testkit/fda_testkit.py activities/<activity_type_id>
```

Replace both placeholders first and use the project environment resolved by
the preflight. Python accepts forward slashes in absolute Windows paths, for
example:

```powershell
& "C:/src/my-activity-project/.venv/Scripts/python.exe" `
  "C:/src/freedeepagents-activity-builder/tools/activity_verifier.py" `
  "C:/src/my-activity-project"
```

The expected output remains at `activities/<activity_type_id>/`. Point FDA Dev
Client / `fda-dev --folder` at that directory.

Static Preview frontend dependencies must be activity-local. If `site/package.json`
uses npm `file:` dependencies, the targets must live inside the activity
directory, such as `file:vendor/<dependency>`. Do not point at the host Runtime
monorepo (`file:../../../packages/...`); verifier rejects those paths because
the synced activity must remain self-contained.

Before those frontend commands, follow
[`references/node-environment.md`](references/node-environment.md). Use
`npm ci` when a lockfile exists; use `npm install` only for the first derivation
without one, then retain the generated `package-lock.json`.

## Verify

A finished activity needs evidence. Run these from `<project-root>` (the repo
holding your `activities/`); `<builder-root>` is where this plugin is installed:

First resolve or create `<project-root>/.venv` using
[`references/python-environment.md`](references/python-environment.md). The
commands below use `<project-python>` for that environment's actual interpreter,
not an arbitrary global Python.

```bash
# 1. static structure + schema conformance (zero deps, no platform repo).
#    Pass <project-root> explicitly; confirm the "scanned N activities" line.
<project-python> <builder-root>/tools/activity_verifier.py <project-root>
# 2. run the activity's Python offline (make_tools + dsl_builder.build)
<project-python> <builder-root>/testkit/fda_testkit.py activities/<activity_type_id>
```

### Toolchain requirements (per tool)

| Tool | Python | Needs platform repo? | Third-party deps |
|---|---|---|---|
| `tools/activity_verifier.py` | **≥ 3.10**（3.9 启动即报错退出——依赖 `sys.stdlib_module_names`） | 否（纯静态 AST） | 无（stdlib only） |
| `testkit/fda_testkit.py` | **≥ 3.9**（实测下限；3.10+ 同样支持） | 否（自带 `app.*` stubs） | 自身零依赖；但它会 import 你的 `tools.py`，其依赖（典型为 `langchain_core`）需自行安装。使用目标 runtime 的同一主版本；当前 FDA 为 LangChain Core 1.x，不要为 testkit 单独降级到 0.3.x |
| `skills/activity-verify/scripts/strict-tool-schema-check.py` | 跟随 FDA 仓库 venv（当前 3.12） | **是**（`tools.py` 的 `app.card_system` import 需仓库在 `sys.path`） | `langchain_core` |
| `tools/check_schema_sync.py` | 跟随 FDA 仓库 venv | **是**（比对 `app.models`，维护者侧守卫） | 平台 venv 全量 |

Static Preview additionally requires Node 20 or 22 and npm 10.x for local
lint/build; Node 20 is the recommended runtime-aligned choice. Card-only has no
Node requirement.

When FDA Dev Client / `fda-dev` is available, sync and smoke the directory:

- Card-only activities must emit `card_item`, `turn_completed`, and `done`.
- Static Preview activities must also serve
  `/preview/<activity_type_id>/<instance_id>/` and
  `/preview/<activity_type_id>/<instance_id>/api/dsl.json`.
- Image activities must validate manifest capabilities, persistent image URLs,
  and image card blocks.

Verifier, strict schema/testkit, and Static Preview build failures block local
completion. A live smoke may be explicitly deferred when the first GUI upload
or authenticated runtime is unavailable; report the exact deferred state.

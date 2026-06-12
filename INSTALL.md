# Install freedeepagents-activity-builder

This package can be used as a Codex plugin, a Claude plugin, or a repo-local
skill symlink. All forms point at the same internal workflow skills.

> **Install the whole package, not individual skills.** The skills cross-link
> each other and the shared `policies/` / `references/` / `workflows/` /
> `schemas/` / `testkit/` dirs with package-relative paths (e.g.
> `../../workflows/06-verify-and-ship.md`). Those resolve only when the full
> package tree is intact. Extracting a single `skills/<one>/` directory into
> `~/.claude/skills/` strands every cross-reference — symlink or copy the
> **entire** `packages/freedeepagents-activity-builder/` directory instead.

## Codex Plugin

The Codex manifest is:

```text
packages/freedeepagents-activity-builder/.codex-plugin/plugin.json
```

Install or register the package with the Codex plugin mechanism used in your
environment. The manifest exposes the internal `skills/` directory and offers
short default prompts such as:

```text
帮我设计并生成一个 FDA 智能活动
Build a FreeDeepAgents activity and package it
Classify this activity idea into Card-only or Static Preview
```

After installation, ask Codex to build an FDA activity. The router will first
run `activity-brief`, then `activity-classifier`, then the builder, frontend,
and packager skills as needed.

## Claude Plugin

The Claude manifest is:

```text
packages/freedeepagents-activity-builder/.claude-plugin/plugin.json
```

In Claude Code, install the package as a local plugin when supported:

```bash
/plugin install /absolute/path/to/packages/freedeepagents-activity-builder
```

安装后，`skills/` 下每个 SKILL.md 都会被**自动发现**并可用 `/<name>` 直接调用——
plugin.json 的 `skills` 数组只是显式声明 + 排序，不是白名单。可直接调的 skill：

主工作流（按顺序）：

```text
/activity-brief         需求澄清
/activity-classifier    分类定型（card-only / static-preview）
/activity-builder       scaffold + 实现（含 card_templates / form 表单卡）
/activity-frontend      Static Preview 前端（仅需要时）
/activity-packager      打包 .fda.tgz + 安装 + 冒烟
```

按需独立工具（随时单独调）：

```text
/activity-verify        静态校验（verifier + strict-tool schema，<5s）
/activity-smoke         端到端冒烟（核 trace.jsonl 的 card_item / turn_completed / done）
/activity-diagnostician 失败排查（turn_id / 错误日志 / 症状 → 根因 + 修复）
```

（`/activity-orchestrator` 是 Codex 侧 router 入口；Claude 用户用根 router
`/freedeepagents-activity-builder` 即可。）

Restart Claude Code if your version scans plugins only at startup.

## Repo-Local Symlink Fallback

If plugin installation is unavailable, expose the package as a project skill:

```bash
cd /path/to/FreeDeepAgents
mkdir -p .claude/skills
ln -s ../../packages/freedeepagents-activity-builder \
  .claude/skills/freedeepagents-activity-builder
```

On systems where symlinks are inconvenient, copy the directory instead:

```bash
cp -R packages/freedeepagents-activity-builder \
  .claude/skills/freedeepagents-activity-builder
```

If you copy instead of symlink, repeat the copy after updating this package.

## Build And Deliver An Activity

The plugin should guide the coding agent through these stages:

1. Write `## Activity Brief`.
2. Write `## Activity Classification`.
3. Generate or update `activities/<activity_type_id>/`.
4. Build `site/dist/` for Static Preview activities.
5. Package the activity:

```bash
bash <package>/tools/pack-activity.sh <activity_type_id>
```

The expected output is a `.fda.tgz` file under `dist/`.

## Install The Package

Install the package in a real FreeDeepAgents repo:

```bash
bash <package>/tools/install-activity.sh /path/to/<activity_type_id>-*.fda.tgz
```

The install script should unpack `activities/<activity_type_id>/`, prepare runtime
dependencies, and rebuild Static Preview assets when needed.

## Verify

A finished activity needs evidence. Run these from `<project-root>` (the repo
holding your `activities/`); `<package>` is where this plugin is installed:

```bash
# 1. static structure + schema conformance (zero deps, no platform repo).
#    Pass <project-root> explicitly; confirm the "scanned N activities" line.
python <package>/tools/activity_verifier.py <project-root>
# 2. run the activity's Python offline (make_tools + dsl_builder.build)
python <package>/testkit/fda_testkit.py activities/<activity_type_id>
```

### Toolchain requirements (per tool)

| Tool | Python | Needs platform repo? | Third-party deps |
|---|---|---|---|
| `tools/activity_verifier.py` | **≥ 3.10**（3.9 启动即报错退出——依赖 `sys.stdlib_module_names`） | 否（纯静态 AST） | 无（stdlib only） |
| `testkit/fda_testkit.py` | **≥ 3.9**（实测下限；3.10+ 同样支持） | 否（自带 `app.*` stubs） | 自身零依赖；但它会 import 你的 `tools.py`，其依赖（典型为 `langchain_core`）需自行安装。平台运行时随 `langchain-community==0.4.1` 携带 `langchain_core` 0.3.x；本地 ≥ 0.3 系即可 |
| `skills/activity-verify/scripts/strict-tool-schema-check.py` | 跟随 FDA 仓库 venv（当前 3.12） | **是**（`tools.py` 的 `app.card_system` import 需仓库在 `sys.path`） | `langchain_core` |
| `tools/check_schema_sync.py` | 跟随 FDA 仓库 venv | **是**（比对 `app.models`，维护者侧守卫） | 平台 venv 全量 |

Then smoke test the installed activity (needs the platform runtime):

- Card-only activities must emit `card_item`, `turn_completed`, and `done`.
- Static Preview activities must also serve
  `/preview/<activity_type_id>/<activity_id>/` and
  `/preview/<activity_type_id>/<activity_id>/api/dsl.json`.
- Image activities must validate manifest capabilities, persistent image URLs,
  and image card blocks.

If any check cannot run, the activity is not ready yet. Report the blocker
instead of claiming success.

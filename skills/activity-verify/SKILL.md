---
name: activity-verify
description: >-
  活动构建第 6 步·开发目录验收。对目标活动目录运行 bundled
  verifier、strict-tool schema 和离线 testkit，形成 Development Verification。
  默认终态是可供 FDA Dev Client / fda-dev 同步的活动目录。
  Use after semantic review to validate an FDA activity directory before Dev
  Client sync or handoff.
---

# Activity Verify

`<builder-root>` 指从本 `SKILL.md` 所在目录向上两级、包含根 `SKILL.md` 与
`tools/` 的目录；不要假定它位于目标项目的 `packages/` 下。

> **何时用**：review 已清零 CONFLICT，要验收开发目录时。默认主链路到这里完成。

完整终态流程和证据格式由
[`../../workflows/06-verify-directory.md`](../../workflows/06-verify-directory.md)
唯一维护；按其顺序执行，不另造一套门禁。

先按 [`../../references/python-environment.md`](../../references/python-environment.md)
解析兼容的项目 Python；没有时用其中的国内镜像 bootstrap 在
`<project-root>/.fda-tools/` + `.venv/` 创建。下列
`<project-python>` 指该环境；仅 strict check 的 `<runtime-python>` 指完整 FDA
runtime 环境。两者都必须替换为实际解释器路径。

## Required deterministic checks

1. **Bundled verifier**（Python ≥3.10、stdlib only）：

   ```bash
   <project-python> <builder-root>/tools/activity_verifier.py <project-root>
   ```

   必须保留完整输出与 `scanned N activities`；不得管给 `grep`。任意 ERROR 阻断。

2. **Strict-tool schema**（仅 manifest 声明 `tools_module` 时）：

   ```bash
   <runtime-python> <builder-root>/skills/activity-verify/scripts/strict-tool-schema-check.py \
     --activity <activity_type_id>
   ```

   使用目标 FDA runtime 的 Python/依赖；普通系统 Python 往往没有
   `langchain_core`。无平台 repo 时由下一项 testkit 覆盖工具 schema。

3. **Offline testkit**：

   ```bash
   <project-python> <builder-root>/testkit/fda_testkit.py activities/<activity_type_id>
   ```

   它运行 `make_tools(ctx)` / `dsl_builder.build()`、校验 typed-KV 写入，并检查
   strict-mode 非法 schema。无 `tools_module` / `dsl_builder_module` 的分支可合法 skip。

Static Preview 还必须先按
[`../../references/node-environment.md`](../../references/node-environment.md)
解析 Node 20/22 + npm 10，再在 `site/` 运行依赖安装、`npm run lint` +
`npm run build`，并确认 `site/dist/index.html`。Card-only 跳过 Node；构建产物
可留在开发目录作为本地证据，但 source sync 会排除 `dist/` 并在服务端重建。

## Development Verification

按 workflow 06 输出 `## Development Verification`：至少包含活动目录、Builder
路径/版本、项目 Python 路径/版本与 reused/created 状态、Semantic review、
Verifier、Strict-tool schema、Testkit；Static Preview 还记录 Node/npm
路径、版本、reused/selected 状态、依赖命令与前端 build；最后记录 warnings 和
changed files。

`development-ready: yes` 要求本地确定性检查全部通过。若已安装并登录 FDA Dev
Client，再转 `../activity-dev-cli/SKILL.md` 用活动目录做 `doctor` / `status` /
`sync --dry-run`，已有首次 GUI 同步时执行
`message --sync-first --new --smoke --pull-logs-on-error`，把真实 turn 证据补进同一
block。首次 GUI 上传尚未完成时记录 deferred，不伪造同步成功。

## Hand-off

- 本地门禁通过 → 交付 `activities/<activity_type_id>/`。
- 共享 dev runtime 可用 → `/activity-dev-cli` → `/activity-smoke`。
- 任一检查失败 → `/activity-diagnostician` 定因 → `/activity-builder` 修复 →
  `/activity-review`（若语义改变）→ 重新 verify。

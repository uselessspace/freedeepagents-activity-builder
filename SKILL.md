---
name: freedeepagents-activity-builder
description: >-
  Use when the user asks to create, scaffold, build, design, develop, or verify
  an FDA / FreeDeepAgents / DeepAgents intelligent activity; asks how to add
  one to the repo; or wants to use fda-dev CLI to
  connect, inspect, sync, pull, smoke-test, or diagnose an activity. Router
  entry for the plugin workflow skills.
---

# FreeDeepAgents Activity Builder

把一个活动点子 → `activities/<activity_type_id>/` 下验证过的开发工程，可直接交给
FDA Dev Client / `fda-dev` 同步。本文件是 Codex + Claude 插件的总入口（router）。
**先认形态，再动手。**

## 我要做的活动属于哪种？（30 秒自测）

活动能力是**叠加**的：人人从 card-only 起步，按需往上加。先在下表对号入座，再开始流程。

| 你的活动需要… | 加什么 | 形态长什么样 |
|---|---|---|
| 聊天 / 卡片 / 表单就够了 | card-only 起步（新活动已含 typed-KV） | [examples/card-only.md](examples/card-only.md) |
| 读取文档、语音转写、生成语音 | + `read_document` / `asr` / `tts_generate` | [policies/capabilities.md](policies/capabilities.md) |
| 生成 / 编辑图片 | + image 能力 | [examples/card-image.md](examples/card-image.md) |
| 一块持久、可检视的可视化界面 | → static-preview | [examples/static-preview.md](examples/static-preview.md) |
| SPA 按钮需要模型理解、Skills 或多工具规划 | static-preview + Preview Agent Turn | [references/preview-agent-turns.md](references/preview-agent-turns.md) |
| SPA 录音后立即得到可编辑文字 | static-preview + direct ASR | [references/preview-asr.md](references/preview-asr.md) |
| Agent 完成读取/操作后让 SPA 切换到语义视图或业务对象 | static-preview + navigation | [references/preview-navigation.md](references/preview-navigation.md) |
| 上传、会话附件、模型/系统生成文件，并在零引用时回收 | + resource lifecycle | [references/asset-lifecycle.md](references/asset-lifecycle.md) |
| 重试、待处理任务或可能跨请求执行的工作 | call-scoped ctx + durable job data | [references/handler-context-lifecycle.md](references/handler-context-lifecycle.md) |

> **名词速查**：**card-system** = 用工具发卡片的输出模式（新活动默认）· **typed-KV** = 活动的结构化业务存储（`data.schema.json` + `data_*` 工具）· **static-preview** = 活动自带的一块 React 前端页面（`site/` + `dsl_builder.py`）。

**设计完全自由。** 核心交付契约是：**卡片可验证**、**工具可调用**、
**业务数据符合 typed-KV schema**、**Static Preview 的 DSL 与交互接口对齐**。
安全、资源归属、身份和能力声明仍按对应 policy 执行。玩法、相位、卡片编排、
前端形态由活动自己设计。拿不准属于哪种？直接走第 1 步。

## 流程（6 步主链路，每步可 `/<name>` 单独调）

1. [`/activity-brief`](skills/activity-brief/SKILL.md) — 点子还模糊？把它问成结构化 Brief。
2. [`/activity-classifier`](skills/activity-classifier/SKILL.md) — 定形态（上表那几个轴），产出 Classification。
3. [`/activity-builder`](skills/activity-builder/SKILL.md) — scaffold + 实现活动文件（含 card_templates / 表单卡）。
4. [`/activity-frontend`](skills/activity-frontend/SKILL.md) — **仅** static-preview 或更丰富前端时。
5. [`/activity-review`](skills/activity-review/SKILL.md) — 语义审查；CONFLICT 必须修复，SMELL/NOTE 可记录取舍。
6. [`/activity-verify`](skills/activity-verify/SKILL.md) — verifier + strict schema + testkit，形成开发目录验收证据。

**按需工具**（也可单独调用）：[`/activity-smoke`](skills/activity-smoke/SKILL.md) 端到端冒烟 · [`/activity-diagnostician`](skills/activity-diagnostician/SKILL.md) 失败排查 · [`/activity-dev-cli`](skills/activity-dev-cli/SKILL.md) 共享 dev runtime 的检查、目录同步、真 turn 与日志。

> **改完想立刻在共享 dev runtime 测一轮？** 先用 `/activity-dev-cli` 做 `doctor` / `status`，再用 `message --sync-first --new --smoke --pull-logs-on-error` 完成同步、真 turn、证据判定和失败日志回收。统一规范见 [`references/dev-agent-cli.md`](references/dev-agent-cli.md)。

> **单一包根原则**：一次构建只使用当前已加载插件包里的 Skill、脚本、模板和
> schema。开始实现前读取该包 `.codex-plugin/plugin.json` 或
> `.claude-plugin/plugin.json` 的版本；不要混用 repo checkout 与旧插件缓存。
> 本 Skill 与子文档中的 `<builder-root>` 就是包含本文件的目录；独立 clone 使用
> 仓库根，只有 monorepo checkout 才使用其 `packages/` 下的 Builder 目录。
> 首次运行 Python 工具前按 [`references/python-environment.md`](references/python-environment.md)
> 检查环境；没有兼容环境时在 `<project-root>/.venv` 新建，不写全局环境、非项目的
> 插件 cache 或最终活动目录。只有 Static Preview 在前端派生/构建前按
> [`references/node-environment.md`](references/node-environment.md) 检查 Node；
> Card-only 跳过，兼容 Node 20/22 + npm 10，优先 Node 20 对齐 runtime。

## 两条铁律（动手前必读）

- **先 Brief 后 Classification 再 scaffold**，不要上来就建文件。完成后的开发工程
  保持在 `activities/<id>/`，由 FDA Dev Client / `fda-dev` 直接同步。
- **活动逻辑只进 `activities/<id>/`**，绝不碰通用 runtime（`app/` / `schemas/`）。完整边界 + 理由见 [`policies/runtime-boundary.md`](policies/runtime-boundary.md)。
- scaffold 中的 `TODO_ACTIVITY_AUTHOR` 是阻断标记，不是示例文案；全部替换后才能 review / verify / sync。

**开发目录完工门禁**由 [`/activity-verify`](skills/activity-verify/SKILL.md)
把关：semantic review `CONFLICT: 0` + verifier 0 ERROR + strict-tool schema +
离线 testkit；共享 dev runtime 可用时再由 `/activity-dev-cli` +
`/activity-smoke` 补真实 `card_item` / `turn_completed` / `done` 证据。证据不齐
就说还差什么，别说“做完了”。

（[`skills/activity-orchestrator/SKILL.md`](skills/activity-orchestrator/SKILL.md) 是 Codex 侧的 router 孪生入口；Claude 用户用本根 router 即可。每个 stage 只读当下需要的那个 subskill，深层细节在 `workflows/` `policies/` `references/`。）

---
name: freedeepagents-activity-builder
description: >-
  Use when the user asks to create, scaffold, build, design, or package a new
  FDA / FreeDeepAgents / DeepAgents intelligent activity, or asks how to add a
  new activity to the repo. Router entry for the plugin workflow skills.
license: MIT
---

# FreeDeepAgents Activity Builder

把一个活动点子 → 验证过的 `.fda.tgz` 包（可装进 FreeDeepAgents repo）。本文件是 Codex + Claude 插件的总入口（router）。**先认形态，再动手。**

## 我要做的活动属于哪种？（30 秒自测）

活动能力是**叠加**的：人人从 card-only 起步，按需往上加。先在下表对号入座，再开始流程。

| 你的活动需要… | 加什么 | 形态长什么样 |
|---|---|---|
| 聊天 / 卡片 / 表单 / 文件就够了 | card-only 起步 | [examples/card-only.md](examples/card-only.md) |
| 记住跨轮的业务数据 | + typed-KV | [examples/card-typed-kv.md](examples/card-typed-kv.md) |
| 生成 / 编辑图片 | + image 能力 | [examples/card-image.md](examples/card-image.md) |
| 一块持久、可检视的可视化界面 | → static-preview | [examples/static-preview.md](examples/static-preview.md) |

> **名词速查**：**card-system** = 用工具发卡片的输出模式（新活动默认）· **typed-KV** = 活动的结构化业务存储（`data.schema.json` + `data_*` 工具）· **static-preview** = 活动自带的一块 React 前端页面（`site/` + `dsl_builder.py`）。

**设计完全自由。** 平台对活动只有三条硬契约：**卡片渲染得出来**（输出符合卡片 schema）、**工具调用得生效**（@tool 参数过 strict 校验）、**Web 产物接得准**（static-preview 时 DSL/接口对得上）。满足契约，玩法、相位、卡片编排、前端形态随你设计——形态只决定你要交付哪些文件，不约束你怎么设计。拿不准属于哪种？直接走流程第 1 步，`/activity-brief` 会帮你问清楚。

## 流程（5 步主链路，每步可 `/<name>` 单独调）

1. [`/activity-brief`](skills/activity-brief/SKILL.md) — 点子还模糊？把它问成结构化 Brief。
2. [`/activity-classifier`](skills/activity-classifier/SKILL.md) — 定形态（上表那几个轴），产出 Classification。
3. [`/activity-builder`](skills/activity-builder/SKILL.md) — scaffold + 实现活动文件（含 card_templates / 表单卡）。
4. [`/activity-frontend`](skills/activity-frontend/SKILL.md) — **仅** static-preview 或更丰富前端时。
5. [`/activity-packager`](skills/activity-packager/SKILL.md) — 打包 `.fda.tgz` + 安装 + 冒烟取证。

**按需工具**（独立于上面链路，随时单独调）：[`/activity-verify`](skills/activity-verify/SKILL.md) 静态校验（<5s 不调 LLM）· [`/activity-smoke`](skills/activity-smoke/SKILL.md) 端到端冒烟 · [`/activity-diagnostician`](skills/activity-diagnostician/SKILL.md) 失败排查。

> **改完想立刻在线上 dev runtime 测一轮?** `fda-dev` CLI 一条命令完成 同步→跑 turn→读事件流→拉日志（`message --sync-first --new --events`）。用法：[`references/dev-agent-cli.md`](references/dev-agent-cli.md)。

## 两条铁律（动手前必读）

- **先 Brief 后 Classification 再 scaffold**，不要上来就建文件。默认交付 `.fda.tgz`。
- **活动逻辑只进 `activities/<id>/`**，绝不碰通用 runtime（`app/` / `frontend-src/` / `schemas/`）。完整边界 + 理由见 [`policies/runtime-boundary.md`](policies/runtime-boundary.md)。

**完工门禁**由 [`/activity-packager`](skills/activity-packager/SKILL.md) 把关：verifier 0 ERROR + 离线 testkit + 安装 + 冒烟（`card_item` / `turn_completed` / `done`）。证据不齐就说还差什么，别说"做完了"。

（[`skills/activity-orchestrator/SKILL.md`](skills/activity-orchestrator/SKILL.md) 是 Codex 侧的 router 孪生入口；Claude 用户用本根 router 即可。每个 stage 只读当下需要的那个 subskill，深层细节在 `workflows/` `policies/` `references/`。）

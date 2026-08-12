---
name: activity-dev-cli
description: >-
  独立工具·FDA 开发运行面。用户或 Coding Agent 要用 fda-dev CLI 检查服务器连通性、
  查看本地/服务器状态、预演或执行同步、拉取服务器源码、运行真实 turn、验证 smoke
  证据或下载日志时使用。Use when developing or debugging an FDA activity
  through the fda-dev CLI, including doctor, status, sync, pull, message,
  smoke, and logs workflows.
---

# Activity Dev CLI

> **何时用**：需要把当前活动接到共享 dev runtime 做“检查 → 同步 → 真 turn → 日志诊断”，或单独查询 CLI 的安全用法时。

本 skill 只负责路由，不复制命令规范。执行前完整读取
[`../../references/dev-agent-cli.md`](../../references/dev-agent-cli.md)，并按其中的
副作用分级、认证边界和结构化输出约定操作。

## 路由

- 连通性、TLS、登录或活动识别问题：`doctor`，再按失败阶段解释。
- 判断本地与服务器关系：`status`。
- 查看即将上传/覆盖什么：先用 `sync --dry-run` 或 `pull --dry-run`。
- `status` 为 `not-synced` / `activityHasPriorSync=false`：停止写操作，
  引导用户在 FDA Dev Client 中完成首次上传；Coding Agent 不得代传。
- 已有至少一次服务器同步后，把本地代码放到开发服务器：确认目标活动后用
  `sync`。
- 跑真实 turn 并检查输出证据：转 `/activity-smoke`，优先使用
  `message --sync-first --new --smoke --pull-logs-on-error`。
- 已有失败 turn 或需要日志：用 `logs` 获取诊断快照，再转
  `/activity-diagnostician`。
- 开发目录验收：CLI 运行证据补进 `/activity-verify` 的
  `Development Verification`；CLI 本身不替代 verifier、strict schema 与离线 testkit。
- FDA Dev Client 的 `sync` 直接读取 `--folder` 指向的活动开发目录。

## 安全提醒

默认从只读检查开始。CLI 具有跨进程的 12 次/分钟、120 次/小时双窗口硬限流；
命中 `CLIENT_RATE_LIMITED` 后必须停止循环并等待 `retryAfterSeconds`，不得用换进程、
换目录或并行调用规避。首次上传只能由用户在 FDA Dev Client 完成。`sync` 会修改
开发服务器，`pull --force` 会覆盖合并本地源码，`login --replace-session` 会替换
当前原生客户端会话；后两者没有用户明确授权不得执行。不要输出 token，也不要
自主扩大附件目录边界。

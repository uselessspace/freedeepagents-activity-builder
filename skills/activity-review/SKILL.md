---
name: activity-review
description: >-
  独立工具·语义级质量自审。由当前在场的编码 agent 执行——通读活动指令/工具/卡片，
  对照活动自身声明的意图 + 插件 policies，找指令自相矛盾、卡片编排不成立、承诺与
  能力错配等"逻辑冲突"。verify 查契约、smoke 验运行，本工具看"设计自不自洽"。
  非阻塞、不动平台、不做发布门槛。活动 agent 定义写完/改完、想自查质量时用。
  Use to self-audit an FDA activity's agent design for logic conflicts the
  deterministic verifier can't catch (contradictory instructions, broken card
  orchestration, promise-vs-capability mismatch). Run BY the in-session coding
  agent; advisory only, no platform code, no gate.
---

# Activity Review

> **何时用**：活动 agent 定义（AGENTS.md / host SKILL.md / tools.py / 卡模板）写完或改完，想做语义自查时。站位：`/activity-verify`（契约）与 `/activity-smoke`（运行）之间的可选一环。

语义级、由**你（在场编码 agent）**亲自读文件并推理——不调外部服务、不需要 API key、不碰同步链路。

## 不做什么（护栏，先记死）

- **只对照活动自己声明的意图**（会话里的 `## Activity Brief`；没有就用 `manifest.description` + AGENTS.md / host SKILL.md 的显式声明）+ 插件 `policies/`。**不引入外部"好活动"参照、不跟别的活动比。**
- **不对玩法、题材、风格、口吻做价值判断**——那是设计自由。
- **不复判** `/activity-verify` 已确定性查过的契约（schema / manifest 白名单 / 工具 strict / doc↔tools.py 名字漂移）。疑似契约错 → 让用户跑 `/activity-verify`，自己不重判。
- 产出永远是"指出 + 定位 + 给修法"，**不替开发者重写**活动。
- **缺持久化 brief 不报问题**——Brief 是会话产物，审存量活动时通常只剩 manifest/skill 文档。

## 输入与扫描面

输入 = 一个活动目录 `activities/<id>/`。通读并交叉比对：

- `manifest.json`（`description` 声明的意图、`input_modes`、`capabilities`）、`runtime.json`（`data_schema_enabled` / timeout / `sse_debug_view` / 模型覆盖等运行配置——**不含相位语义**）。
- `AGENTS.md` + host `SKILL.md` + `skills/**`（指令与玩法叙事）。
- `tools.py`（@tool 真实签名 / docstring）。
- `card_templates/*.json` + `*.vars.json`（卡片契约）。
- `data.schema.json`（typed-KV 业务态，若有；相位看这里的业务 `phase` + 卡模板 `meta.phase` + host skill 路由，别去 runtime.json 找）。

## 六维评审

逐维过 [references/review-rubric.md](references/review-rubric.md)：① 指令自洽 ② 卡片编排逻辑 ③ 工具叙事一致 ④ 承诺↔能力匹配 ⑤ 输出纪律落位 ⑥ 意图达成。

## 判级

- **CONFLICT（逻辑冲突 / 硬伤）** — 两条指令不能同时成立，或指令与契约/工具现实矛盾。
- **SMELL（质量异味）** — 自洽性弱、易跑偏、承诺与能力不一致但尚未到"兑现不了"。
- **NOTE（优化建议）** — 可选打磨。

全部**非阻塞**：本工具产出报告，不是门槛。

## 输出契约

每条 finding 固定四件套：`[维度] · 文件:行 · 问题一句话 · 修法一句话`。

```markdown
## Activity Review — <activity_type_id>
- 评审基准：<一句话复述 Activity Brief 或 manifest/skill 显式声明的意图> + policies
- CONFLICT: <n>  SMELL: <n>  NOTE: <n>

### CONFLICT
1. [指令自洽] AGENTS.md:L40 要求"每轮必发 result 卡"，但 SKILL.md:L88 "无候选时跳过发卡" —— X 情况下二者冲突。
   修法：把 result 卡改成有条件发，或在 L40 加例外。

### SMELL
…（同结构）

### NOTE
…

### 下一步
- 有 CONFLICT → /activity-builder 改 → /activity-verify 复核契约。
- 仅 SMELL/NOTE → 自行取舍。
```

## 何时跑 / hand-off

- `activity-builder` 写完或改完 agent 定义后、打包前；可选。
- **不进 `activity-packager` 完工门禁**——保持自审、不阻塞。
- 有 CONFLICT → `/activity-builder` 改 → `/activity-verify` 复核契约；仅 SMELL/NOTE → 自行取舍。

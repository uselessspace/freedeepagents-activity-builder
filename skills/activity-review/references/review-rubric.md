# Review Rubric — 六维 Agent 质量自审清单

> 评审基准只有两个来源：**活动自己声明的意图**（会话里的 `## Activity Brief`，没有就用 `manifest.description` + AGENTS.md / host SKILL.md 的显式声明）+ 本插件 `policies/`。
> **不引入外部"好活动"参照、不跟别的活动比、不对玩法/题材/口吻做价值判断。**

每条 finding 固定四件套：`[维度] · 文件:行 · 问题一句话 · 修法一句话`。判级见 SKILL.md（CONFLICT / SMELL / NOTE）。

---

## 1. 指令自洽
**查什么**：AGENTS.md / host SKILL.md / `skills/**` 内部有无**互斥指令**——两条不能同时成立。
**典型冲突**：
- 「每轮必发 X 卡」 vs 某分支「某情况下不发 X 卡」。
- 「保持简短」 vs 「逐条详尽展开」。
- 同一工具被要求以矛盾方式调用。
**锚**：纯逻辑矛盾，无 policy；这是 review 的主战场。

## 2. 卡片编排逻辑
**查什么**：指令要求的发卡时序成不成立。
**典型冲突**：
- 先发结果卡，再去采集填充它的数据（时序倒置）。
- prose **主动指示** `assignment_id` 按次序递增（`x_1`/`x_2`）——同一逻辑卡每轮换 ID，前端误判多张、live-update 失效。host skill 这么写即 CONFLICT（指令与 card-system 契约矛盾）。
- 描述了永远到不了的相位/分支。
**锚**：`policies/llm-output-discipline.md`（§1 assignment_id）+ `policies/output-protocol.md`。

## 3. 工具叙事一致
**查什么**：prose 对某工具「何时调 / 怎么调」的描述，与它在 `tools.py` 的真实签名/docstring 是否矛盾；有无工具存在却没有任何指令给 agent 调它的理由。
**注意**：**不复判** verify 已确定性查过的「引用了不存在的工具」（doc↔tools.py 名字漂移）——那是 `/activity-verify` 的活。本维度只看"存在但叙事自相矛盾/无理由"。
**锚**：`policies/multi-store-tool-design.md`、`policies/tool-error-protocol.md`。

## 4. 承诺↔能力匹配
**查什么**：活动**显式声明要做的事**，跟它实际拥有的工具/卡片/输入模式是否对得上。**只按显式承诺判，不按口吻/题材判。**
**典型冲突**：
- `manifest.description` 声明"读上传 PDF"，但 `manifest.input_modes` 无 `file`、`manifest.capabilities` 无 `read_document` → 兑现不了（CONFLICT）。
**不报**：活动没声明读文件，缺文档能力不算问题；自称"严谨"而提示词口语化属设计自由。

## 5. 输出纪律落位
**查什么**：host SKILL.md 是否把 `policies/llm-output-discipline.md` 要求的护栏写进去——字面 `assignment_id`（非拼接）、不让 LLM 直接拼最终 JSON 输出、artifact 的 `url`/`path` 规则、图片 artifact 由 runtime 自动 surface（不手动 artifact_emit）。
**缺护栏**（该写的护栏没写）= 易跑偏 → SMELL。**注意边界**：若 host skill **主动指示**了某个破坏契约的反模式（如主动让 assignment_id 递增），那是维度 2 的 CONFLICT，不在这里降级成 SMELL；本维度只管"该写的护栏没写"。
**锚**：`policies/llm-output-discipline.md` + `policies/agents-md-thin.md` + `policies/output-protocol.md`。

## 6. 意图达成
**查什么**：活动**自己声明的目标**有无「指令 + 工具 + 卡片」端到端的支撑链。缺口 = agent 兑现不了承诺。
**注意**：这是哲学锚——对照活动**自己的意图**，不是"它本可以更丰富"。功能没声明就缺，不是缺陷。
**锚**：活动 brief / manifest.description 自身。

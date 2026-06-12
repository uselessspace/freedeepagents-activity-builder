# Reference — 输出校验工具箱

> **定位**：解决"我的活动跑完一轮，输出对不对、错在哪一层"的问题。Card-system 模式下，绝大部分校验已经在工具调用时立即发生——本文件只覆盖**事后人工 review** 和**trace 离线复验**两种场景。

## Card-system 模式：校验发生在哪里

所有新活动都跑在 card-system 模式。在这种模式下，校验是**前置 + 即时**的：

| 时机 | 校验点 | 错了怎样 |
|---|---|---|
| LLM 调每个 card-system 工具 | tool 入参 pydantic + dry-apply（平台仓库 `app/card_system/tools.py`） | 立刻返 `ToolMessage(error=...)`，LLM 改单条调用 retry |
| LLM 调 `data_set` / `data_append` / 活动 @tool | 整 store 写入后立即按 `data.schema.json` dry-validate；失败回滚写入 | 立刻返 `ToolMessage(error=...)` 附 schema 报错原文，LLM 改单条调用 retry |
| `card_emit_template` | `variables` 校验对应 `*.vars.json` + 模板渲染后整卡符合 `MinimalAICard`（平台仓库 `app/card_templates.py`） | 同上，附 `available_templates` 提示 |
| Turn 结束 | `assemble(turn_dir)` 按 seq 顺序汇编非 retracted 条目（平台仓库 `app/card_system/assemble.py`） | 汇编后的 `ActivityAgentOutput` 由 pydantic 再过一遍——但因为单条已校验过，这里几乎不会失败 |

结论：**新活动联调时，不需要在写 SKILL.md 时手工跑 sample 校验**。LLM 真实调用每个工具时已经被立即校验，错误立刻反馈，比"返 1KB JSON 全错"反馈快得多。

## 何时仍需手工校验

1. **活动行为不符合预期**：跑了一轮，前端展示出问题——用本文档的 trace 复验定位是 LLM 出错还是 runtime 汇编出错。
2. **写 `card_templates/<id>.json` 时**：你写的是**模板源文件**，不是 LLM 输出——可以用 `MinimalAICard.model_validate` 验一下模板渲染后是否合法。
3. **改 `data.schema.json`**：改完后过一遍现有 instance 的 `data.json`，确认旧实例还能通过新 schema（不通过的字段 LLM 会拿到错误并自动重写）。

## Trace 离线复验（端到端跑完后回查）

每个 turn 在 `runtime/instances/<activity_type_id>/<activity_id>/turns/<tid>/` 留下完整 trace。常用入口：

```bash
TURN_DIR=runtime/instances/<activity_type_id>/<activity_id>/turns/<tid>

# A) 看本轮 LLM 发了哪些工具调用 + 返回了什么
jq -c 'select(.event | test("^(tool_call|tool_result)$"))' "$TURN_DIR/trace.jsonl"

# B) 看本轮汇编后的最终 ActivityAgentOutput
cat "$TURN_DIR/agent_output.json" | jq .

# C) 看 LLM 最终响应（应该没有用户可见正文；可见输出来自工具调用）
jq -c 'select(.event == "agent_raw_result") | .payload.result' "$TURN_DIR/trace.jsonl" | tail -1
```

### 常见错误模式 → 该看哪一条

| 现象 | 看 | 含义 |
|---|---|---|
| 前端没显示卡片 | `agent_output.json` 的 `cards` 数组 | 是 LLM 没调 `card_emit*`，还是调了被 retract，还是汇编漏了 |
| 前端卡片渲染异常 | `card_templates/<id>.<name>.json` + `*.vars.json` | 模板字段名错 / variables 不匹配 schema |
| state / 业务数据未更新 | trace 里 `tool_call: data_set`/`data_append`/活动 @tool 的 `tool_result` | 写 `data.json` 失败（schema 校验失败？）；runtime 派生的 phase/counts/last_*_id 来自 emit 的卡片，不是手写的 |
| LLM 一直卡在中间态 | trace 里的 `card_emit*` / `mark_status` 序列 | 检查 host SKILL.md fast-path table 有没有"必须 emit 终态卡并在完成时 mark_status"那行 |

## 写法约束

- **活动私有字段一律放进 `data.schema.json`**；共享层 `schemas/activity-output.schema.json` 由 runtime 维护，活动只读不改（详见 [policies/runtime-boundary.md](../policies/runtime-boundary.md)）
- **state 改动一律通过工具调用**（活动 @tools 或 `data_*` / card-system tools）走 schema 校验路径
- **预检流程靠跑一轮端到端**：card-system 模式下 LLM 不直接产出 `ActivityAgentOutput`，所以预先手写一份 sample JSON 验不出真实问题

## 相关文件

随包分发（外部可解析）：

- 数据模型 schema：[../schemas/card-template.schema.json](../schemas/card-template.schema.json) / [../schemas/output-artifact.schema.json](../schemas/output-artifact.schema.json)
- card-system 工具对照表：[card-system-tools.md](card-system-tools.md)
- LLM 易踩坑：[../policies/llm-output-discipline.md](../policies/llm-output-discipline.md)

平台仓库源头（仅维护者可达，路径供对照）：`app/card_system/tools.py`（工具实现）、
`app/card_system/assemble.py`（汇编逻辑）、`app/models.py`（数据模型）。

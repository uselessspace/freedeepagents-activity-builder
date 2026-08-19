---
name: template-activity-host
description: >-
  TODO_ACTIVITY_AUTHOR: describe the template activity's business intents and
  when this host router must run.
---

# 模板活动主技能

本 Skill 是活动业务意图与相位的唯一权威。AGENTS.md 只负责把本活动交给这里；
cards Skill 只负责卡片呈现，不重复业务路由。

## Authoring gate

- 发布前删除所有 `TODO_ACTIVITY_AUTHOR`，把本文件改成真实活动的薄路由。
- 详细生成规则、判断标准和多步流程放进本 Skill 目录的 `workflows/`、
  `policies/` 或 `references/`，这里只保留选择入口。
- 卡片模板与字面 `assignment_id` 以
  `/activity/skills/template-activity-cards/SKILL.md` 为准。

## Always apply

- 本活动使用 card-system；所有用户可见输出通过 `card_emit_template`、
  `card_emit` 或 `artifact_emit` 产生。不要返回最终 JSON，工具调用完成后停止。
- 业务数据使用 Classification 选定的 SQLite / typed-KV / hybrid 模式。
  SQLite 只能由活动 @tools/handlers 通过 `ctx.database` 访问；typed-KV 才使用
  `data.schema.json` 和 `data_*`。Agent 不接触 SQL 或数据库文件。
- 固定业务卡使用模板中声明的字面 `assignment_id`，同一逻辑卡跨 turn 复用。
- 图片工具返回的 artifact 由 runtime 自动登记，只把返回的 `file_url` 放入卡片，
  不再手动调用 `artifact_emit`。
- 终态才调用 `mark_status("completed" | "failed")`；调用后结束本轮。
- 工具失败时按错误修正参数，避免用相同参数循环重试；不可用能力必须给用户可见降级说明。

## Route map

| 触发 | 执行 |
|---|---|
| 首次进入、帮助或重置完成 | `card_emit_template("template-activity.welcome", {}, "template-activity-welcome")` 后停止 |
| 关键信息不足 | 发 `template-activity.intake`，使用 `template-activity-intake`，等待用户 |
| 业务请求 | TODO_ACTIVITY_AUTHOR: route to one skill-local workflow and list its allowed tools |
| 闲聊或不支持的请求 | 发一张简短说明卡，不启动外部能力 |

## Turn boundary

每条业务路由必须明确本轮是“等待用户”还是“完成业务”。只有确实需要用户补充信息时
才停在 intake；能在同一 turn 完成的工作应在发出结果卡后再结束。不要发一张没有后续
恢复机制的 progress 卡就停止。

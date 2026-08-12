---
name: template-activity-cards
description: >-
  TODO_ACTIVITY_AUTHOR: describe the fixed card templates owned by the template
  activity and when the host router emits them.
---

# 模板活动卡片技能

本 Skill 只定义固定卡片的呈现契约；用户意图与业务相位由 host Skill 唯一路由。

## Authoring gate

- 发布前删除所有 `TODO_ACTIVITY_AUTHOR`，把欢迎文案、表单字段和模板字典改成真实活动。
- 每个固定模板都必须有同名 `.vars.json`；欢迎卡必须完全静态且变量 schema 为空。
- 长变量目录拆到本 Skill 的 `references/`，不要继续拉长入口文件。

## 模板字典

| template_id | assignment_id（字面） | 何时调用 | 必需变量 |
|---|---|---|---|
| `template-activity.welcome` | `template-activity-welcome` | 首次进入、帮助、重置完成 | 无；只能传 `{}` |
| `template-activity.intake` | `template-activity-intake` | 关键信息不足 | `title`, `body`, `topic`, `constraints` |

## 调用示例

```text
card_emit_template(
    "template-activity.welcome",
    {},
    "template-activity-welcome",
)
```

## 卡片纪律

1. `assignment_id` 从上表逐字复制；同一逻辑卡跨 turn 保持不变。
2. 固定业务卡走 `card_emit_template(...)`；真正一次性的短提示才用 `card_emit(...)`。
3. `variables` 传实际值；`{{var}}` 只存在于非 welcome 的模板源文件。
4. 长报告与文件走 artifact，不塞进卡片正文。

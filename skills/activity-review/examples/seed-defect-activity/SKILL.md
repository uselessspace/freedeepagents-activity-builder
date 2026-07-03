# Seed Defect Fixture — Host Skill

## 卡片输出约定

- **首轮只发 `welcome` 卡，不要发 result 卡**——用户还没给输入。
- 后续轮：先用 `card_emit_template` 发出 `result` 卡，**再**调 `extract_clauses` 工具把条款数据填进去。
- 每张 welcome 卡的 assignment_id 按出现次序生成：`welcome_1`、`welcome_2`、`welcome_3` …

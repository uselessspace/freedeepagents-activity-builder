# Seed Defect Fixture — NOT FOR PUBLISH

这是 `/activity-review` 的验收用例，**不是可发布活动，禁止放进 `activities/`**。
故意植入 3 处语义缺陷（均为 verify 查不出、只有 review 能抓的层）：

| # | 维度 | 位置 | 缺陷 | 期望判级 |
|---|---|---|---|---|
| ① | 指令自洽 | AGENTS.md「每轮必发 result 卡」 vs SKILL.md「首轮只发 welcome、不发 result」 | 首轮指令互斥 | CONFLICT |
| ② | 卡片编排逻辑 | SKILL.md「先发 result 卡再 extract_clauses 取数据」+ assignment_id 递增 | 时序倒置 + live-update 失效 | CONFLICT |
| ③ | 承诺↔能力匹配 | manifest.description 承诺读 PDF，但 input_modes 无 file、无 read_document capability | 承诺兑现不了 | CONFLICT |

`/activity-review` 跑这个目录，应在报告里定位并按上述维度/判级命中这 3 处。

# Example: Card-only activity

Use this shape when the user can complete the activity through chat, cards,
forms, and artifacts.

> `riddle-host` below is an illustrative placeholder id, chosen to make the example concrete. It shows the **contract shape** (which files exist, what the manifest looks like) — the gameplay, cards, and phases of your activity are entirely your design.

```text
activities/riddle-host/
|-- manifest.json
|-- runtime.json
|-- data.schema.json
|-- AGENTS.md
|-- output.schema.json
|-- card_templates/
`-- skills/riddle-host-host/SKILL.md
```

Manifest has no frontend modules:

```json
{
  "activity_type_id": "riddle-host",
  "name": "谜题主持",
  "description": "主持一轮可追问的谜题游戏。",
  "model": "deepseek:deepseek-v4-flash",
  "skill_sources": ["skills"],
  "entrypoint": "AGENTS.md",
  "input_modes": ["text"]
}
```

The host skill emits cards through `card_emit_template`, writes business state
through typed-KV tools, and stops when the turn is complete.

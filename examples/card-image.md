# Example: Card-only with image tools

Use this when the activity returns images but does not need a persistent
frontend.

> `poster-maker` below is an illustrative placeholder id. It shows the contract shape (capability declaration + persistent-URL flow) — what you generate and how you present it is your design.

Manifest:

```json
{
  "activity_type_id": "poster-maker",
  "name": "海报生成器",
  "description": "根据用户输入生成一张海报并用卡片返回。",
  "model": "deepseek:deepseek-v4-flash",
  "skill_sources": ["skills"],
  "entrypoint": "AGENTS.md",
  "input_modes": ["text", "image"],
  "capabilities": ["image_generate", "image_edit"]
}
```

Flow:

1. Use `image_generate` for fresh images.
2. Use `image_edit` only when the user provides an image or the brief requires
   a locked reference.
3. Persist any long-lived reference URL in typed-KV through an activity tool.
4. Emit a card image block with the returned persistent URL.

No `site/` is required.

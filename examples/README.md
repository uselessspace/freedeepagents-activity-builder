# Examples

Concrete shapes for current activity routes.

| File | Route | Use when |
|---|---|---|
| [card-only.md](card-only.md) | Card-only | Cards, forms, and artifacts are enough |
| [card-typed-kv.md](card-typed-kv.md) | Card-only + typed-KV | The activity needs durable business state |
| [card-image.md](card-image.md) | Card-only + image tools | The activity returns generated or edited images in cards |
| [static-preview.md](static-preview.md) | Static Preview | New frontend activities need a persistent visual surface |

For new frontend activities, choose Static Preview: `site/`, `dsl_builder.py`,
optional `tools.py`, and built `site/dist/`.

> The activity ids in each example file (`riddle-host`, `checklist-coach`, `poster-maker`, `project-map`) are illustrative placeholders — they are not real activities. Each example shows the **contract shape** (files, manifest fields, schema structure) for its route. Design — gameplay, phases, cards, UI — is not constrained by these examples; the platform contract is the only boundary (cards validate, tools call cleanly, the web surface wires up).

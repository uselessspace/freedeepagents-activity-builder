# Workflow 05: optional frontend polish

Use this only for Static Preview activities when the user explicitly asks for a
stronger visual result. Core runtime correctness comes first.

## Principle

Use external UI libraries, shadcn examples, or local UI skills as inspiration
only. Do not vendor external skill source into this package. Activity-specific
frontend code belongs in `activities/<id>/site/`.

## Minimal stack

The `frontend-base/` includes Tailwind v4 for layout and responsive styling.
Keep that dependency set until the selected design actually imports more:

```bash
# Run only the line whose packages the activity will import.
npm install motion lucide-react
npm install clsx tailwind-merge
```

Use `motion` for restrained transitions, `lucide-react` for recognizable
icons, and `clsx` + `tailwind-merge` only when component variants need them.
The install updates the activity's `package.json` and lockfile; never add all
four speculatively.

## Polish Budget

Pick one visual emphasis:

| Activity type | Good polish | Avoid |
|---|---|---|
| utilitarian dashboard | dense tables, filters, clear status, compact motion | oversized hero sections |
| game-like interactive | animated state transitions, feedback, progress | decorative effects that obscure rules |
| visual canvas | zoom/pan affordances, selected-object states | cards around the whole canvas |
| timeline | readable sequence, now/next markers | excessive parallax |
| graph | stable nodes, hover details, fit-to-view | shifting layout on hover |
| pet/avatar | stateful sprite, mood, gentle loops | animations that fight controls |
| form workflow | stepper, validation, review state | hidden required fields |

## Manual Pattern

Use small, local components inside `activities/<id>/site/src/components/`.

```tsx
import { motion } from 'motion/react';

export function FadeInPanel({ children }: { children: React.ReactNode }) {
  return (
    <motion.section
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.28, ease: 'easeOut' }}
    >
      {children}
    </motion.section>
  );
}
```

Rules:

- Use 1-2 motion ideas per screen.
- Use lucide icons for tools and status actions.
- Use shadcn-style component structure for tabs, menus, dialogs, inputs, and
  tables, but implement only what the activity needs.
- Check mobile and desktop screenshots before directory verification.

## Hand-off

```text
Frontend polish for <id> complete.
Proceeding to 06-verify-directory.md.
```

# Policy: one error at a time

## Rule

When the verifier reports multiple errors, **fix the first one only, then re-run**. Don't batch.

## Why

Verifier errors interact:
- Fixing manifest may trigger state-schema re-evaluation
- Renaming a skill may break SKILL.md path discovery
- "Quick" warnings sometimes introduce new ERRORs

Batch fixes mean you don't know which change caused what when something breaks.

## Correct loop

```
1. Run verifier
2. Read the FIRST error line
3. Make the smallest change that addresses it
4. Re-run verifier
5. Did the first error disappear?
   YES → next error (back to step 2 with the new "first")
   NO  → revert step 3 and try a different fix
```

## Anti-pattern

```
1. Verifier shows 8 errors
2. "I see the pattern, let me fix all 8 at once"
3. Verifier shows 5 errors (3 you fixed, 2 were side-effects of the fix)
4. Try to fix 3 more
5. Verifier shows 4 errors (different again)
6. Lost track
```

## When you genuinely can't fix an error

- Re-read the error message + the relevant section of [../references/verifier-checks.md](../references/verifier-checks.md)
- Check if it's a design problem (then go back to upstream workflow, e.g. re-do
  `data.schema.json` typed-KV shape)
- If it's a verifier bug (rare), report to the user — do NOT modify the verifier yourself

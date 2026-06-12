# Policy: multi-store tool design — let one tool wrap the side-effects

## Rule

When a user-visible intent ("记一下…" / "保存…" / "登记…") needs to fan
out to **multiple stores** (typed-KV + secondary index + derived
search DB + …), expose **one** tool to the agent — the one matching
user semantics — and do the multi-store writes **inside the tool's
implementation as best-effort side-effects**.

Do NOT expose every store's CRUD as its own @tool and rely on the
agent to call them in order.

## Why

Splitting one user intent across N tools is a recipe for the kind of
"agent thinks it did the thing, half the data is missing" bug you can't
catch by schema validation:

- Agent forgets one of the N — that store goes stale, the next turn's
  read returns inconsistent state, agent gets confused and "fixes" it
  by writing more. Cascades.
- Agent picks the wrong subset because the routing table is ambiguous
  ("用户说'记住 X' — is that add_note or gbrain_put or both?"). One
  ambiguity = one prompt to fix; ten = a maintenance graveyard.
- Reviewer cannot tell from a single `add_note` call whether the
  knowledge graph also got updated. Tools that hide their fan-out
  are easier to reason about than tools that depend on a sibling
  being called next.

The agent should choose **intent**, not **persistence layout**.

## Anti-pattern (do NOT)

```python
# tools.py — one tool per store, agent has to chain them
@tool
def add_note(content, tags=[]) -> dict:
    typed_kv.append("notes", {...})
    return {"ok": True}

@tool
def gbrain_put(slug, markdown) -> dict:
    gbrain.write_page(slug, markdown)
    return {"ok": True}
```

```markdown
# SKILL.md — agent now has to remember the dance
| 用户说"请记住 X" | 先 `add_note(X)` 然后 `gbrain_put(slug, ...)` |
| 用户说"存到知识库" | 仅 `gbrain_put(slug, ...)` |
```

Real bug this caused in `ai-secretary` (platform-repo commit `b36d6b0`): the agent
saw "请记住 X" and only called `gbrain_put`, leaving the typed-KV
`notes[]` empty. Next turn's "查看记忆" read `notes[]` and showed
nothing — agent looked like it lied to the user.

## Correct shape

```python
@tool
def add_note(
    content: str,
    tags: list[str] | None = None,
    entity_updates: list[dict] | None = None,
) -> dict:
    """Append a note (and optionally compile facts into entities).

    Side-effects (all best-effort, failures logged not raised):
    - mirror to gbrain as notes/<id>
    - auto-stub any [[type/slug]] wikilink targets
    - apply entity_updates: append text to Compiled Truth / Timeline
    """
    note = {...}
    typed_kv.append("notes", note)               # main store
    try:
        gbrain.mirror_note(note)                 # side-effect 1
        gbrain.auto_stub_wikilinks(note.content) # side-effect 2
        gbrain.apply_updates(entity_updates)     # side-effect 3
    except Exception:
        log.exception("gbrain side-effects failed for %s", note["id"])
    notify_dsl_update()                          # side-effect 4
    return {"ok": True, "id": note["id"], ...}
```

```markdown
# SKILL.md — one routing entry per user intent
| 用户说"请记住 X" | `add_note(content=X, entity_updates=[...])` |
```

Agent makes **one call**; tool fans out internally. The user's
intent and the tool name match 1:1.

## When to expose extra read tools

It's fine to expose secondary stores for **reads** — `gbrain_search`,
`gbrain_get`, `gbrain_list` are legitimate because they answer
different questions and don't risk inconsistency.

The rule is about **writes that originate from one user intent**.
Read tools have no fan-out problem.

## When to break the rule

- **Importing data that doesn't come from a user intent** (e.g.
  bulk-loading a company directory): a low-level write like
  `gbrain_put` is fine — the agent is acting as an admin, not
  fielding a user request.
- **Repairing inconsistency** (e.g. an agent-facing
  `recompile_entity(slug)` that triggers a full rewrite): also fine,
  these are explicit-intent rare paths.

These are exits to the low-level interface, not the default path.

## Side-effects must be best-effort

If the secondary store fails, the **main store write must still
succeed** and the user must still see their action took effect.
Wrap each side-effect in `try / except / log`, never let a search
index hiccup throw away the user's note.

## Verifier signal (future)

The verifier (`tools/activity_verifier.py`) can grow a heuristic:
if a SKILL routing table has the **same user intent** mapped to
two write tools called in sequence, emit a WARNING and link here.
Not implemented yet — file an issue when you have a second example
to motivate it.

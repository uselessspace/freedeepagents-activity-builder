#!/usr/bin/env python3
"""Parse an FDA turn's trace.jsonl and assert the smoke evidence standard.

A turn is considered smoke-passing when its trace contains at least one
``card_item``, ``turn_completed``, and ``done`` SSE event. Reports the
distribution of every SSE event type for context, and surfaces the first
error event so the operator can route to ``activity-diagnostician``.

Pure stdlib. Exit 0 = PASS, 1 = FAIL, 2 = bad input.
"""

from __future__ import annotations

import argparse
import collections
import json
import pathlib
import sys

REQUIRED_EVENTS = ("card_item", "turn_completed", "done")
ERROR_EVENTS = ("llm_error", "chain_error", "tool_error", "turn_error")

# Signatures of the runtime's zero-emit fallback card. Source: app/service.py
# emits a card with template "runtime.zero_emit_fallback", assignment_id
# "runtime-zero-emit-fallback", and meta.kind "zero_emit_failure" when an
# entire turn produced no activity emits. Any of these three is sufficient to
# identify a fallback so we don't count it as a valid user-visible card.
_FALLBACK_TEMPLATE = "runtime.zero_emit_fallback"
_FALLBACK_ASSIGNMENT_ID = "runtime-zero-emit-fallback"
_FALLBACK_META_KIND = "zero_emit_failure"


def _is_zero_emit_fallback_card(card_item_payload: dict) -> bool:
    """Return True iff this card_item payload is the runtime's fallback card."""
    if card_item_payload.get("assignment_id") == _FALLBACK_ASSIGNMENT_ID:
        return True
    card = card_item_payload.get("card") or {}
    if card.get("template") == _FALLBACK_TEMPLATE:
        return True
    meta = card.get("meta") or {}
    if meta.get("kind") == _FALLBACK_META_KIND:
        return True
    return False


def _classify_row(row: dict) -> tuple[str, str | None, bool]:
    """Return (sse_type, error_snippet_or_None, is_fallback_card) for one trace row.

    The trace wraps SSE events under {event: "sse_event", payload: {type: ..., payload: {...}}}.
    Non-SSE events keep their own `event` key (chain_start, llm_error, ...).
    `is_fallback_card` is True only for `card_item` events whose payload matches
    the runtime zero-emit fallback signature.
    """
    event = row.get("event")
    if event == "sse_event":
        sse_envelope = row.get("payload") or {}
        sse_type = sse_envelope.get("type") or "<unknown sse>"
        is_fallback = False
        if sse_type == "card_item":
            inner_payload = sse_envelope.get("payload") or {}
            is_fallback = _is_zero_emit_fallback_card(inner_payload)
        return sse_type, None, is_fallback
    if event in ERROR_EVENTS:
        msg = (row.get("payload") or {}).get("error") or json.dumps(row.get("payload") or {})[:200]
        return event, msg, False
    return event or "<unknown>", None, False


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("trace_jsonl", help="path to runtime/instances/.../turns/<id>/trace.jsonl")
    args = ap.parse_args()

    path = pathlib.Path(args.trace_jsonl)
    if not path.is_file():
        print(f"error: trace.jsonl not found at {path}", file=sys.stderr)
        return 2

    counts: collections.Counter = collections.Counter()
    fallback_card_count = 0
    first_error: tuple[str, str] | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        sse_type, error_msg, is_fallback = _classify_row(row)
        counts[sse_type] += 1
        if is_fallback:
            fallback_card_count += 1
        if error_msg and first_error is None:
            first_error = (sse_type, error_msg)

    # Effective user-visible card count excludes the runtime fallback card.
    effective_card_items = counts.get("card_item", 0) - fallback_card_count

    print("==> trace.jsonl summary")
    for ev_type in sorted(counts, key=lambda k: (-counts[k], k)):
        suffix = ""
        if ev_type == "card_item" and fallback_card_count:
            suffix = f"  (of which {fallback_card_count} is zero-emit fallback)"
        print(f"  {ev_type}: {counts[ev_type]}{suffix}")

    # Fallback present → unambiguous E5 (zero-emit fallback). No matter what
    # turn_completed / done say, the user only saw the generic "AI 本轮未能
    # 给出有效回答" card. Surface it as the diagnosis hint.
    if fallback_card_count:
        print("\n==> Smoke: FAIL")
        print("  cause: zero-emit fallback present — the activity emitted no real card this turn")
        print("  → maps to error class E5 (skills/activity-diagnostician/references/error-classes.md)")
        if first_error:
            ev_type, msg = first_error
            print(f"  first error event: {ev_type} — {msg[:200]}")
        print("==> Route to activity-diagnostician with this turn_id.")
        return 1

    missing = [e for e in REQUIRED_EVENTS if counts.get(e, 0) < 1]
    if not missing and effective_card_items < 1:
        # Defensive: card_item events all happen to be fallback (fallback_card_count
        # already caught this above) OR every card_item was filtered out. Treat
        # as missing card_item.
        missing.append("card_item (no non-fallback cards)")

    if missing:
        print("\n==> Smoke: FAIL")
        print(f"  missing: {', '.join(missing)}")
        if first_error:
            ev_type, msg = first_error
            print(f"  first error: {ev_type} — {msg[:200]}")
        print("==> Route to activity-diagnostician with this turn_id.")
        return 1

    print(f"\n==> Smoke: PASS  ({' ≥ 1, '.join(REQUIRED_EVENTS)} ≥ 1)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

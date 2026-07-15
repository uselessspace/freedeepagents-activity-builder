# Agent-driven Static Preview navigation

Static Preview activities can let an Agent focus or navigate the already-open
SPA after a successful read or action. This is a transient UX signal, not
durable business state and not a manifest capability.

## Runtime contract

Activity-owned tools or handlers receive this helper on their runtime context:

```python
ctx.emit_preview_navigation(
    {
        "surface": "document",
        "target_id": record_id,
        "focus_id": section_id,
        "stage": "reading",
    }
)
```

- Pass a JSON-serializable `dict`. Field names and meanings are private to the
  activity; the generic runtime does not interpret them.
- The runtime adds `event_id` (`pn-...`) and the current `turn_id`, then emits a
  named `preview_navigate` event on the existing `/api/dsl/stream` SSE.
- Delivery is scoped to the current activity type, activity instance, and
  authenticated `ctx.user_id`. Activity code must not select or put a target
  user id in the payload.
- Every subscribed tab for that same user and instance may receive the event.
- Delivery is best-effort: the event is not persisted or replayed, no active
  subscriber is a no-op, and a slow consumer can miss an event.

Call it only after the operation that justifies the navigation has succeeded.
Do not emit for every search candidate, retry, token, or intermediate step.
Navigation is observational UX: failure to deliver it must never make the
business tool fail. Do not call `notify_dsl_update()` solely for navigation.

## SPA contract

Use the same EventSource as DSL refresh. Do not open a second stream:

```ts
source.addEventListener('preview_navigate', (event) => {
  const navigation = JSON.parse(event.data) as PreviewNavigationEvent;
  // Validate activity-private fields, then select/scroll/focus.
});
```

The packaged `frontend-base` already wires this event into `useDsl()`:

```tsx
const { data, navigation } = useDsl();

useEffect(() => {
  if (!navigation || navigation.surface !== 'document') return;
  selectRecord(String(navigation.target_id));
  scrollToSection(String(navigation.focus_id));
}, [navigation]);
```

Narrow `PreviewNavigationEvent` with an activity-owned type guard before using
private fields. Treat duplicate `event_id` values idempotently. If the UI needs
navigation history across a tab refresh, store that tab-only history in
`sessionStorage`; if state must survive devices or sessions, put it in typed-KV
and project it through `dsl_builder.py` instead.

Local `npm run dev` uses mock DSL and does not reproduce runtime SSE delivery.
Unit-test the event-to-selection logic locally, then verify the real event
through the installed preview URL.

## Author checklist

- [ ] Classification is `frontend_axis: static-preview` and
  `navigation_axis: agent-to-preview`.
- [ ] Payload contains only JSON-safe activity identifiers and display state;
  no secret, raw file bytes, or user-routing fields.
- [ ] Backend emits after a successful operation and catches/logs any optional
  navigation failure without failing the operation.
- [ ] SPA consumes `preview_navigate` on the existing DSL stream and validates
  activity-private fields.
- [ ] Duplicate or missing events are harmless; durable truth remains in DSL /
  typed-KV.
- [ ] Two-user test confirms the other user on the same instance receives
  nothing.
- [ ] Installed-runtime test confirms focus/scroll works and ordinary DSL SSE
  updates still render.

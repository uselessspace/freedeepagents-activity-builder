# Reference — Activity `ctx` lifecycle and deferred work

Use this reference whenever `tools.py` or `handlers.py` calls `ctx.*`,
`ctx.llm.*`, or starts work that may continue after the current call returns.

## The hard boundary

`ctx` is a call-scoped capability, not a process-global service object:

| Entry point | `ctx` remains valid until |
|---|---|
| Activity `@tool` created by `make_tools(ctx)` | the current Agent turn/tool lease ends |
| SPA handler created by `make_handlers(ctx)` | that handler returns or raises |
| `dsl_builder.build(instance_dir)` | no `ctx` is provided; read the instance files only |

Do not retain `ctx`, `ctx.llm`, a bound `ctx.*` method, or a closure containing
them in module globals, queues, timers, threads, tasks, executor jobs, or
callbacks that can run later. Once the call ends, the runtime revokes its
capability token. A late callback then fails with:

```text
Activity capability token is invalid or expired
```

HTTP 200 does not change this rule. A handler may return `{"ok": true}` after
enqueueing work, while that detached work fails later and writes a failure
state that the next `dsl.json` request renders.

## Correct patterns

### Finish capability work before returning

Keep provider calls and state mutation in the active handler:

```python
def make_handlers(ctx):
    def classify(text: str) -> dict:
        if ctx.llm is None:
            return {"ok": False, "error": "llm unavailable"}
        result = ctx.llm.chat_json(
            system='Return JSON: {"category": "...", "confidence": 0.0}.',
            user=text,
        )
        save_result(result)
        ctx.notify_dsl_update()
        return {"ok": True, "result": result}

    return {"classify": classify}
```

Return only after every `ctx`-dependent operation has completed.

### Persist jobs as data, resume with a fresh `ctx`

When work must be split across requests:

1. Persist only plain JSON-safe job data: job id, resource ref, status, retry
   count, and immutable inputs.
2. Do not persist Python callbacks, closures, bound methods, or `ctx`.
3. On `resume_pending_jobs`, rebuild the work from stored data and use the
   current handler's `ctx`.
4. Complete that unit of `ctx`-dependent work before the resume handler
   returns.
5. For more work, persist the next checkpoint and let another request resume
   it with another fresh `ctx`.

```python
def make_handlers(ctx):
    def resume_pending_jobs(limit: int = 1) -> dict:
        if ctx.llm is None:
            return {"ok": False, "error": "llm unavailable"}
        jobs = load_pending_jobs(limit=limit)
        completed = []
        for job in jobs:
            result = ctx.llm.chat_json(
                system='Process one queued item and return JSON: {"result": "..."}.',
                user=job["prompt"],
            )
            mark_completed(job["job_id"], result)
            completed.append(job["job_id"])
        if completed:
            ctx.notify_dsl_update()
        return {"ok": True, "completed": completed}

    return {"resume_pending_jobs": resume_pending_jobs}
```

## Concurrency that is allowed

Local concurrency is allowed only when it cannot outlive the call:

- Join every started thread before returning.
- Await every task/future before returning.
- Never discard an executor future.
- Never use framework background-task hooks for `ctx`-dependent work.

Prefer direct synchronous code unless measured latency justifies concurrency.
The verifier rejects obvious detached patterns when they carry `ctx`, such as
`asyncio.create_task(run(ctx))`, unawaited executor calls that receive `ctx`,
`Thread(target=lambda: ctx.*).start()`, and ctx-dependent threads started
without a matching `join()`. Activity-owned background work that never retains
or calls `ctx` is outside this capability-lifecycle rule; it must still manage
its own resources and remain inside the Activity Type boundary.

## Error handling

Do not copy the raw capability-token error into activity-visible state. Map it
to a stable activity error code and a user-facing retry message, while keeping
the original exception in activity logs for diagnosis. This improves the UI
but does not make a stale `ctx` valid.

## Review checklist

- [ ] No module global stores `ctx`, `ctx.llm`, or bound `ctx.*` methods.
- [ ] No thread/task/callback continues after its tool or handler returns.
- [ ] Pending jobs contain plain data only.
- [ ] Every resume operation uses the current `make_handlers(ctx)` context.
- [ ] Every `ctx`-dependent future is joined/awaited before return.
- [ ] A 200 response is not treated as proof that deferred work completed.

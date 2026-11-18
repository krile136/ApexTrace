# TraceHistory and TraceUsage details

## TraceHistory

One entry per lifecycle call, in call order. `TraceFlow.getAllHistories()` returns a copy of the list; `TraceFlow.lastHistory()` returns the last entry or `null`.

| Method | Returns |
|---|---|
| `getType()` | `TraceHistory.HistoryType`: `Start`, `Log`, `Skip`, `Abort`, `Finish` |
| `isStart()` / `isLog()` / `isSkip()` / `isAbort()` / `isFinish()` | `Boolean` |
| `getContextName()` | the context the entry belongs to |
| `getMessage()` | the message, or `null` (always `null` for `Start`, and for closes called without a message) |
| `containsText(text)` | `true` when the message contains `text`; `false` for `null` text or message |
| `getUsage()` | inclusive `TraceUsage` on `Skip` / `Abort` / `Finish`; `null` on `Start` and `Log` |
| `getTimestamp()` / `getDateTime()` | when the entry was recorded |

```apex
for (TraceHistory history : TraceFlow.getAllHistories()) {
  if (history.getUsage() != null) {
    System.debug(history.getContextName() + ' ' + history.getUsage().format());
  }
}
```

### Entries written outside the normal flow (production only)

In production (Relaxed mode) a lifecycle call on a Trace that is not running is skipped and leaves a `Log` entry whose message starts with `ignored: `:

```
ignored: Finish on "Close opportunities as lost" (that Trace is not running: finished already, or never started).
```

The entry belongs to the context that was current at the time, or to the misused Trace when nothing was running. When a lifecycle call comes on a running Trace while Traces above it are still open, each of those is closed with an `Abort` entry with "Automatically aborted due to context mismatch. Expected context: {name}". Tests run in Strict mode, where these cases throw instead.

## Inclusive and exclusive usage

| Where the usage comes from | What it covers |
|---|---|
| `TraceHistory.getUsage()`, `TraceFlow.lastUsage()`, the `Usage:` line in the debug log | inclusive: everything between the context's `start()` and its close, nested children included |
| `TraceFlow.usageOf(name)`, `TraceFlow.usagesOf(name)` | exclusive: the inclusive usage minus the inclusive usage of the direct child contexts |

Example: a handler context runs unit A (2 queries) and unit B (4 queries) and issues no query itself.

| Context | Inclusive | Exclusive |
|---|---|---|
| handler | 6 | 0 |
| A | 2 | 2 |
| B | 4 | 4 |

Summing inclusive values would count 12 queries for a transaction that ran 6. When only the leaf units are traced, inclusive and exclusive are equal.

Untraced work inside a context (plain code, or triggers whose code has no Trace) counts toward that context.

## Invocations

- `usageOf(name).getInvocations()` is the number of times a context with that name closed, nested re-entries included. Every close counts: `finish`, `skip` and `abort`.
- Each element of `usagesOf(name)` has `getInvocations() == 1`.
- Invocations are not split between parent and child. Consumption and invocations are separate measures.
- A context that never closed (an exception passed it without `abort`) recorded no usage and is not counted.

## format()

`TraceUsage.format()` returns one line:

```
SOQL: 3 (rows: 120), DML: 1 (rows: 30), Callouts: 0
Invocations: 2, SOQL: 3 (rows: 120), DML: 1 (rows: 30), Callouts: 0
```

The `Invocations:` prefix appears when the count is not 1 (an aggregate from `usageOf`, including a zero aggregate).

## Internal members

`TraceUsage.zero()`, `plus()`, `capture()` and `since()` are public only so `TraceFlow` can use them. Don't build usage arithmetic on them in tests: `since()` always returns an invocation count of 1, so a difference of two aggregates loses the count. To measure only the Act, call `TraceFlow.discardArrange()` before it.

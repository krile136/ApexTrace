---
name: apex-trace-logging
description: Adding ApexTrace lifecycle logging to Apex production code (services, use cases, batch or queueable bodies, trigger-called logic). Use when writing or fixing code that calls Trace.of / start / log / skip / abort / finish, choosing between finish, skip and abort, closing a Trace in a catch block before rethrowing, nesting Traces when one traced unit calls another, keeping the Trace instance in a field or local variable, reading START / SKIP / ABORT / FINISH / Usage lines in the debug log, the difference between Strict mode (tests) and Relaxed mode (production), "ignored: Finish on ..." history entries, and TraceException errors such as "Trace context is undefined. Please execute the start method of the Trace instance.", "The context for Finish operation is not the current context.", "a different Trace with the same name", "Context name is null." or "Context name is empty." Use in a project that contains Trace.cls. Not for editing ApexTrace's own source.
---

# ApexTrace: Logging with Trace

`Trace` marks the start and the end of a unit of processing as a named context. Each context opens with `start()`, may write `log()` lines, and closes with exactly one of `finish()`, `skip()` or `abort()`. Contexts nest like a stack. Every call writes a debug log line and a history entry; closing a context also records the governor usage it consumed. Tests read that history through `TraceFlow` (see `apex-trace-testing`).

## Rules

1. Create a Trace once per unit with `Trace.of(name)` and keep the instance. Call every lifecycle method on that instance. Never re-create it with `Trace.of(name)` to close it: matching is by instance, not by name.
2. Call `start()` before any `log()`, `skip()`, `abort()` or `finish()`.
3. Close every started Trace on every path: `finish` when the work was done, `skip` when there was nothing to do, `abort` when the work failed.
4. When an exception can leave the unit, catch it, call `abort(...)`, and rethrow. Every traced level that the exception passes through does the same, innermost first.
5. Close inner Traces before outer ones (last in, first out).
6. Use one constant for the context name and reuse it in tests (`TraceFlow.usageOf(NAME)`). The name is the key that tests and logs use.
7. Don't call the `TraceFlow` methods marked internal (`push`, `log`, `skip`, `finish`, `abort`, `pop`, `ensureContext`, `currentContextName`, `isEmpty`). Use the `Trace` instance.
8. Don't put secrets or personal data in names or messages. They go to the debug log as is.

## API

| Method | Purpose |
|---|---|
| `Trace.of(String name)` | Creates a Trace. `null` or `''` throws `TraceException` ("Context name is null." / "Context name is empty."), in tests and in production |
| `t.start()` | Opens the context and takes a usage snapshot |
| `t.log(String message)` | Writes a line inside the context. A `null` or `''` message is recorded as "Trace log message is null." / "... is empty." There is no overload without an argument |
| `t.finish()` / `t.finish(String result)` | Closes the context as done |
| `t.skip()` / `t.skip(String reason)` | Closes the context as "nothing to do" |
| `t.abort()` / `t.abort(String reason)` | Closes the context as failed |
| `t.getContextName()` | The name given to `Trace.of` |

Choose the closing call by what happened, because tests assert on it:

| Outcome | Call |
|---|---|
| The unit did its work | `finish` |
| The unit returned early on purpose (no input, nothing changed, condition not met) | `skip` |
| The unit could not complete (exception, business error) | `abort` |

## Example

```apex
public with sharing class OpportunityLossService {
  @TestVisible
  static final String TRACE_NAME = 'Close opportunities as lost';

  private final Trace t = Trace.of(TRACE_NAME);

  public Integer closeAsLost(Set<Id> opportunityIds) {
    this.t.start();

    if (opportunityIds == null || opportunityIds.isEmpty()) {
      this.t.skip('No opportunity to close.');
      return 0;
    }

    try {
      List<Opportunity> opportunities = [
        SELECT Id, StageName
        FROM Opportunity
        WHERE Id IN :opportunityIds AND IsClosed = false
      ];
      this.t.log(opportunities.size() + ' open opportunities found.');

      for (Opportunity opportunity : opportunities) {
        opportunity.StageName = 'Closed Lost';
      }
      update opportunities;

      this.t.finish(opportunities.size() + ' opportunities closed as lost.');
      return opportunities.size();
    } catch (Exception e) {
      this.t.abort(e.getMessage());
      throw e;
    }
  }
}
```

- The Trace may live in a field (as above) or in a local variable of the method. What matters is that the same instance is started and closed.
- A field Trace can be started again after it was closed, so one instance can serve several calls on the same object.

## Nesting

When a traced unit calls another traced unit, the inner context opens and closes inside the outer one.

```apex
Trace parentTrace = Trace.of('Renew account contracts');
parentTrace.start();

Trace childTrace = Trace.of('Create renewal opportunities');
childTrace.start();
childTrace.log('inside the child');
childTrace.finish();      // child first

parentTrace.log('child done');
parentTrace.finish();     // then parent
```

- `parentTrace.log(...)` or `parentTrace.finish()` while `childTrace` is still open is out of order.
- `outer` and `inner` are reserved words in Apex. Don't use them as variable names.
- A unit that calls itself runs two Traces with the same name. They stay separate, because matching is by instance.
- Usage recorded on a closed context includes the usage of the contexts nested inside it. `TraceFlow.usageOf(name)` subtracts the direct children, so tests can target each name (see `apex-trace-testing`).

## Strict mode and Relaxed mode

The mode is chosen automatically by `Test.isRunningTest()`. Production code cannot switch it. `TraceFlow.changeModeTo(...)` is `@TestVisible private` and exists for ApexTrace's own tests.

| Situation | Strict (tests) | Relaxed (production) |
|---|---|---|
| Lifecycle call while no Trace at all is open | throws `TraceException` "Trace context is undefined. Please execute the start method of the Trace instance." | call is skipped and recorded as an `ignored:` Log entry |
| Call on a Trace that is open but not the current one (an inner Trace was left open) | throws "The context for {Operation} operation is not the current context." with both names | the Traces above it are aborted with "Automatically aborted due to context mismatch. Expected context: {name}", then the call proceeds |
| Call on a Trace that is not running (finished twice, never started, re-created with `Trace.of`) while another Trace is open | throws "...is not the current context."; when the current context has the same name, the message adds "The current context is a different Trace with the same name: ..." | call is skipped; a WARN debug line and a Log entry "ignored: Finish on "{name}" (that Trace is not running: finished already, or never started)." are recorded |
| `Trace.of(null)` / `Trace.of('')` | throws | throws |

- Relaxed mode never throws from a lifecycle call, so tracing cannot stop a business transaction in production. It also means mistakes surface only in tests. Cover each path with a test.
- A Trace left open with no later lifecycle call on it stays open until the transaction ends. Nothing records its close or its usage.
- Strict mode is what turns a missing `abort` into a test failure: if an inner unit lets an exception escape without aborting, the outer unit's `abort` (or the test's own wrapping Trace) throws "not the current context", and that `TraceException` replaces the original exception.

## Debug log format

| Call | Line |
|---|---|
| `start()` | `START: {name} is starting` |
| `log(m)` | `{name}: {m}` |
| `finish()` / `finish(r)` | `FINISH: {name}` / `FINISH: {name}` + `Result: {r}` |
| `skip()` / `skip(r)` | `SKIP: {name} is skipped` / `SKIP: {name} is skipped for the following reason.` + `Reason: {r}` |
| `abort()` / `abort(r)` | `ABORT: {name} is aborted.` / `ABORT: {name} is aborted for the following reason.` + `Reason: {r}` |

Every closing line ends with a usage line for that context, including nested children:

```
FINISH: Close opportunities as lost
Result: 3 opportunities closed as lost.
Usage: SOQL: 1 (rows: 3), DML: 1 (rows: 3), Callouts: 0
```

Usage covers SOQL queries, SOQL rows, DML statements, DML rows and callouts. CPU time and heap are not measured.

## Where to put a Trace

- Trace the units whose path or cost you want to see and assert on: a service method, a use case, the body of a batch `execute` or a queueable.
- Tests find a context by name with `TraceFlow.usageOf(name)`, so a trigger handler does not need its own Trace for usage assertions on the units it calls.
- A Trace around a trigger handler makes logs easier to read (each 200-record chunk and each re-entry shows as its own frame), but it must be closed on every path of every trigger event, like any other Trace.

## Common mistakes

| Symptom | Cause | Fix |
|---|---|---|
| Test throws "The context for Finish operation is not the current context." and the message says "a different Trace with the same name" | The code closes a Trace created with a second `Trace.of(name)` | Keep the started instance and call `finish` on it |
| Test throws "Trace context is undefined..." | `log` / `finish` / `skip` / `abort` before `start()`, or after the context already closed, while no other Trace is open. With the test's own wrapping Trace open, the same mistake throws "...is not the current context." instead | Call `start()` first; close once |
| Test throws "...is not the current context." in an outer `abort` or in the test's own `finish` | An inner unit let an exception escape without aborting, or returned early without closing | Close the inner Trace on every path: `skip` before early returns, `abort` in a `catch` |
| The original exception is hidden by a `TraceException` in tests | Same as above: the outer `abort` runs while the inner context is still open | Abort at every traced level, innermost first |
| Production log shows "Automatically aborted due to context mismatch" | An inner Trace was left open and Relaxed mode cleaned it up | Find the path that does not close the inner Trace |
| Production history has "ignored: Finish on ..." | `finish` called twice, or on a re-created Trace | Close once, on the started instance |
| `TraceException` "Context name is null." in production | `Trace.of` received a `null` name (for example from an unset variable) | Use a constant name |
| A renamed context breaks usage tests | Tests repeat the name as a literal | Share one `TRACE_NAME` constant between the class and its tests |
| No `FINISH` line or usage for a unit in the log | The method returned or threw without closing | Add `skip` / `abort` on those paths |

---
paths: ["**/*.cls", "**/*.trigger"]
---

# ApexTrace

This project traces its processing with ApexTrace (`Trace.cls`, `TraceFlow`, `TraceUsage`).

- Create a Trace once with `Trace.of(name)`, keep the instance, and call `start()`, `log()`, `skip()`, `abort()` and `finish()` on that same instance. A Trace re-created with `Trace.of(name)` is a different Trace, even with the same name.
- Close every started Trace on every path: `finish` on success, `skip` when there was nothing to do, `abort` on failure (also in a `catch` before rethrowing). Close inner Traces before outer ones.
- Don't call `TraceFlow.push / log / skip / finish / abort / pop / ensureContext` or `TraceUsage.capture / since / plus / zero`. They are internal.
- In tests, assert the path with `TraceFlow.isLastFinish()` / `isLastSkip()` / `isLastAbort()` next to the assertions on side effects.
- Assert governor usage with `TraceFlow.usageOf(name)` and loose upper bounds, in tests that run real DML. Don't use `TraceFlow.lastUsage()`.
- Call `TraceFlow.discardArrange()` at the Arrange / Act boundary, next to `Test.startTest()`, before asserting a path or usage.
- Write test descriptions (the `Trace.of(...)` text in tests) and assert messages in the language the project's tests already use, and keep its case labels (for example `正常系:` / `異常系:` / `エッジケース:`, or `Normal:` / `Error:` / `Edge:`).
- Before writing code, load the matching skill: `apex-trace-logging` for `Trace` in production code, `apex-trace-testing` for `TraceFlow` path checks and `TraceUsage` assertions.

These rules don't apply to ApexTrace's own source and tests (`Trace.cls`, `TraceFlow.cls`, `TraceHistory.cls`, `TraceUsage.cls`, `TraceException.cls`, `LimitsReader.cls`, `ILimitsReader.cls` and `tests/`).

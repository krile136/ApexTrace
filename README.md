# ApexTrace

**A lightweight execution flow tracing framework for Salesforce Apex that combines logging and test assertion capabilities.**

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Coverage](https://img.shields.io/badge/Coverage-98%25-brightgreen.svg)](#test-coverage)

## 🌟 Overview

ApexTrace is an innovative framework that manages the start-to-end lifecycle of processing as explicit "contexts", ensuring the order and nested structure of execution flow. It serves **dual purposes**:

1. **Development & Debugging**: Visualize complex execution flows with hierarchical logging
2. **Testing**: Assert execution paths and outcomes using structured history

Unlike traditional logging frameworks, ApexTrace provides:

- ✅ **Strict context management** with automatic nesting validation
- ✅ **Test-friendly API** for asserting execution flow
- ✅ **Zero configuration** - works out of the box
- ✅ **Lightweight** - minimal performance overhead

## 📦 Installation

### Using Makefile (Recommended)

```bash
$ cd force-app/main/default/classes
$ git submodule add https://github.com/krile136/ApexTrace.git ApexTrace

# Install to your org
make install

# Run tests
make test

# Show all available commands
make help
```

### Manual Installation

Copy the following files to your project:

- `Trace.cls`
- `TraceFlow.cls`
- `TraceHistory.cls`
- `TraceException.cls`

## 🔧 Makefile Commands

ApexTrace includes a Makefile for convenient operations:

| Command                    | Description                        |
| -------------------------- | ---------------------------------- |
| `make install`             | Deploy ApexTrace to your org       |
| `make uninstall`           | Remove ApexTrace from your org     |
| `make reinstall`           | Uninstall and reinstall ApexTrace  |
| `make test`                | Run all ApexTrace tests            |
| `make test-trace`          | Run Trace tests only               |
| `make test-traceflow`      | Run TraceFlow tests only           |
| `make test-tracehistory`   | Run TraceHistory tests only        |
| `make test-traceexception` | Run TraceException tests only      |
| `make test-all`            | Run all tests with detailed output |
| `make help`                | Show available commands            |

### Quick Commands

```bash
# Install and test in one go
make install test

# Reinstall (useful after making changes)
make reinstall

# Run specific test class
make test-trace
```

## 🚀 Quick Start

### Basic Usage

```apex
public class QuoteProcessor {
  public void process(Quote__c quote) {
    Trace trace = Trace.of('QuoteProcessor.process');
    trace.start();

    if (quote == null) {
      trace.skip('Quote is null');
      return;
    }

    try {
      // Your processing logic
      Integer count = processQuote(quote);
      trace.finish('Processed: ' + count + ' line items');
    } catch (Exception e) {
      trace.abort('Error: ' + e.getMessage());
      throw e;
    }
  }
}
```

### Output

```
START: QuoteProcessor.process is starting
QuoteProcessor.process: Processing quote Q-12345
QuoteProcessor.process: Calculated totals
FINISH: QuoteProcessor.process
Result: Processed: 5 line items
```

## 📚 Core Concepts

### Trace Lifecycle

Every trace follows a simple lifecycle:

```apex
Trace trace = Trace.of('ContextName');  // 1. Create
trace.start();                           // 2. Start
trace.log('Processing...');              // 3. Execute (optional)
trace.finish();                          // 4. End (finish/skip/abort)
```

### Operations

| Operation        | Purpose                | When to Use                |
| ---------------- | ---------------------- | -------------------------- |
| `start()`        | Begin a trace context  | At the start of processing |
| `log(message)`   | Log intermediate steps | During processing          |
| `skip(reason)`   | Skip processing        | Early return conditions    |
| `finish(result)` | Complete successfully  | Normal completion          |
| `abort(reason)`  | Terminate abnormally   | Exception handling         |

### Nested Contexts

ApexTrace automatically manages nested contexts:

```apex
Trace outer = Trace.of('OuterProcess');
outer.start();

  Trace inner = Trace.of('InnerProcess');
  inner.start();
  inner.log('Inner processing');
  inner.finish();

outer.log('Outer processing');
outer.finish();
```

**Important**: Always finish inner contexts before operating on outer contexts. Violations throw `TraceException`.

## 🧪 Testing with ApexTrace

### Basic Test Pattern

```apex
@isTest
static void testProcess_WhenValidData_ThenFinished() {
  // Arrange
  TraceFlow.clear();  // Always clear before test
  Quote__c quote = createTestQuote();

  // Act
  new QuoteProcessor().process(quote);

  // Assert
  Assert.isTrue(TraceFlow.isLastFinish());
  Assert.isTrue(TraceFlow.lastHistoryContains('Processed: 1'));
}
```

### Asserting Execution Flow

```apex
@isTest
static void testProcess_WhenNullQuote_ThenSkipped() {
  // Arrange
  TraceFlow.clear();

  // Act
  new QuoteProcessor().process(null);

  // Assert - Verify the execution was skipped
  Assert.isTrue(TraceFlow.isLastSkip());
  Assert.isTrue(TraceFlow.lastHistoryContains('Quote is null'));
}

@isTest
static void testProcess_WhenError_ThenAborted() {
  // Arrange
  TraceFlow.clear();
  Quote__c invalidQuote = createInvalidQuote();

  // Act & Assert
  try {
    new QuoteProcessor().process(invalidQuote);
    Assert.fail('Exception should have been thrown');
  } catch (Exception e) {
    Assert.isTrue(TraceFlow.isLastAbort());
    Assert.isTrue(TraceFlow.lastHistoryContains('Error:'));
  }
}
```

### Advanced Assertions

```apex
// Get all execution history
List<TraceHistory> histories = TraceFlow.getAllHistories();
Assert.areEqual(3, histories.size());  // start + log + finish

// Check stack depth (for nested contexts)
Integer depth = TraceFlow.getStackDepth();
Assert.areEqual(0, depth);  // All contexts should be closed

// Get history count
Integer count = TraceFlow.getHistoryCount();
Assert.areEqual(5, count);
```

### Governor Usage Tracking

Every context automatically records the governor limit consumption between its
`start()` and its close (`finish()` / `skip()` / `abort()`). The consumption is
appended to the debug log of the closing entry and can be asserted in tests:

```apex
new QuoteRecalculationUsecase(quoteIds).invoke();

// Assert the governor cost of the traced section (chainable)
TraceFlow.lastUsage()
  .assertSoqlQueriesAtMost(3)
  .assertDmlStatementsAtMost(1);

// Every assert takes an optional reason — printed in the failure message,
// right where the person about to raise or delete the threshold reads it
TraceFlow.usageOf('QuoteRecalculation')
  .assertInvocationsAtMost(6, 'measured 5 on a 201-record insert; a jump means an extra trigger wiring')
  .assertSoqlQueriesAtMost(15, 'must not scale with record count');

// Or inspect the raw numbers
TraceUsage usage = TraceFlow.lastUsage();
System.debug(usage.getSoqlQueries());   // SOQL queries issued
System.debug(usage.getSoqlRows());      // rows returned by SOQL
System.debug(usage.getDmlStatements()); // DML statements issued
System.debug(usage.getDmlRows());       // rows processed by DML
System.debug(usage.getCallouts());      // callouts made

// Usage is attached to the history entry that closed the context
TraceUsage sameUsage = TraceFlow.lastHistory().getUsage();
```

Notes:

- Only deterministic metrics are tracked (SOQL queries / SOQL rows / DML statements / DML rows / callouts). CPU time and heap are intentionally excluded because they fluctuate between runs.
- A parent context's usage includes its nested children (everything consumed between start and close).
- Assertion helpers throw a catchable `TraceException` (instead of `Assert.fail`) with the full usage breakdown, so failures are testable and self-explanatory.
- `lastUsage()` guards against ambiguity: in test execution it throws when two or more contexts closed at the same level (a handler that ran several usecases — `lastUsage()` would silently measure only the last one), listing the candidates to paste into `usageOf(...)`. Production is never affected.
- Consumption asserts (`assertSoqlQueriesAtMost` etc.) on a context that **never ran** (`usageOf` with no match, invocations = 0) throw instead of passing vacuously — a typo'd context name, the wrong test layer, or missing wiring all surface immediately. Asserting that a context does *not* run stays legitimate: `assertInvocationsAtMost(0)`.
- Debug logs now show the cost of each section, e.g. `FINISH: QuoteRecalculation\nUsage: SOQL: 3 (rows: 120), DML: 1 (rows: 30), Callouts: 0`.

### Scoping the observation window: discardArrange()

Trace history accumulates from the top of the test method — Arrange DML that
fires triggers leaves the traced usecases in the history, polluting both the
usage numbers and the path asserts. Discard it at the Arrange / Act boundary,
right next to the `Test.startTest()` you already write:

```apex
setupData();                 // Arrange — trigger-driven usecases traced here

TraceFlow.discardArrange();  // ← same boundary
Test.startTest();

new SomeUsecase(ids).invoke();
Test.stopTest();

TraceFlow.usageOf('SomeUsecase')      // Act only — invocations are correct too
  .assertInvocationsAtMost(1)
  .assertSoqlQueriesAtMost(0, 'issues nothing when there is no diff');

Assert.isTrue(TraceFlow.isLastSkip());   // path asserts are Act-scoped as well
```

Only the history is discarded — a Trace opened before the call (the test's own
wrapper) still closes correctly. In test execution, calling it while a usecase
context is open throws (it would silently drop that context); at the boundary,
at most the wrapping Trace is open. Forgetting the call cannot be detected by
the library — but `assertInvocationsAtMost` is the natural sentinel: an
Arrange-time invocation bumps the count and fails the assert, which is one more
reason to always start with the invocation bound.

### Per-context aggregation: usageOf()

`lastUsage()` only returns the most recently closed context — when a trigger
handler runs several usecases, that is just the last one. `usageOf(name)`
aggregates **every** invocation of the named context in the transaction:

```apex
Test.startTest();
insert opportunities;   // real DML → the whole trigger cascade fires
Test.stopTest();

// "runs exactly once per save" — an extra trigger wiring shows up as a jump
// in invocations before any SOQL threshold trips
TraceFlow.usageOf('RegenerateCollection').assertInvocationsAtMost(1);

// bulk-safe: 30 records must not mean 30x the queries
TraceFlow.usageOf('AggregateX02ToX01')
  .assertInvocationsAtMost(4)
  .assertSoqlQueriesAtMost(10);

// per-invocation breakdown when you need it
List<TraceUsage> each = TraceFlow.usagesOf('AggregateX02ToX01');
```

How to read a failure: **too many invocations → suspect the wiring** (the
usecase is triggered from more entry points than intended); **invocations fine
but consumption per invocation high → suspect the usecase's internals** (a
query in a loop).

Aggregation rules:

- Consumption is summed as **exclusive** usage — each invocation's own
  consumption minus its nested children — so nested re-entries of the same
  context (trigger cascades) are not double-counted, and work done by
  differently-named children is attributed to them, not to the parent.
- `getInvocations()` counts every close, nesting included: "invoked 13 times
  for 39 queries in total" reads off one object. On `lastUsage()` and
  `usagesOf()` entries it is always `1`.
- No match returns a zero object (0 invocations), never null. Invocation
  asserts work on it (`assertInvocationsAtMost(0)` = "must not run"); consumption
  asserts throw, because bounding the consumption of something that never ran is
  an unfounded claim. Contexts that never closed (an exception unwound past
  them) recorded no usage and are not counted.
- Unlike raw `Limits` reads, `usageOf()` works after `Test.stopTest()`
  (`stopTest()` rolls the governor counters back to their pre-`startTest()`
  values, silently blinding any later `Limits.getQueries()` assert) — and it
  is the only way to bound the consumption of **asynchronous** work (batch /
  queueable), which only executes at `stopTest()`.
- ⚠️ In pure unit tests where SOQL/DML is mocked, every usage is zero and any
  `assert...AtMost` passes vacuously — usage assertions belong in integration
  tests with real DML.

## 🎯 Use Cases

### 1. Service Layer

```apex
public class AccountService {
  public void updateAccounts(List<Account> accounts) {
    Trace trace = Trace.of('AccountService.updateAccounts');
    trace.start();

    if (accounts == null || accounts.isEmpty()) {
      trace.skip('No accounts to update');
      return;
    }

    trace.log('Updating ' + accounts.size() + ' accounts');

    try {
      update accounts;
      trace.finish('Updated: ' + accounts.size());
    } catch (DmlException e) {
      trace.abort('DML Error: ' + e.getMessage());
      throw e;
    }
  }
}
```

### 2. Batch Processing

```apex
public class AccountBatch implements Database.Batchable<sObject> {
  public void execute(Database.BatchableContext bc, List<Account> scope) {
    Trace trace = Trace.of('AccountBatch.execute');
    trace.start();

    trace.log('Processing ' + scope.size() + ' records');

    Integer successCount = 0;
    Integer errorCount = 0;

    for (Account acc : scope) {
      Trace itemTrace = Trace.of('AccountBatch.processAccount');
      itemTrace.start();

      try {
        processAccount(acc);
        itemTrace.finish();
        successCount++;
      } catch (Exception e) {
        itemTrace.abort('Error: ' + e.getMessage());
        errorCount++;
      }
    }

    trace.finish('Success: ' + successCount + ', Errors: ' + errorCount);
  }
}
```

### 3. Trigger Handler

```apex
public class QuoteTriggerHandler {
  public void onBeforeInsert(List<Quote__c> quotes) {
    Trace trace = Trace.of('QuoteTriggerHandler.onBeforeInsert');
    trace.start();

    trace.log('Validating ' + quotes.size() + ' quotes');
    validateQuotes(quotes);

    trace.log('Calculating totals');
    calculateTotals(quotes);

    trace.finish('Processed: ' + quotes.size());
  }
}
```

## 🔧 API Reference

### Trace

| Method                         | Description                |
| ------------------------------ | -------------------------- |
| `Trace.of(String contextName)` | Create a new trace context |
| `start()`                      | Start the trace context    |
| `log(String message)`          | Log a message              |
| `skip()`                       | Skip with no reason        |
| `skip(String reason)`          | Skip with reason           |
| `finish()`                     | Finish with no result      |
| `finish(String result)`        | Finish with result         |
| `abort()`                      | Abort with no reason       |
| `abort(String reason)`         | Abort with reason          |

### TraceFlow

| Method                             | Description                         |
| ---------------------------------- | ----------------------------------- |
| `isEmpty()`                        | Check if trace stack is empty       |
| `isLastStart()`                    | Check if last operation was start   |
| `isLastLog()`                      | Check if last operation was log     |
| `isLastSkip()`                     | Check if last operation was skip    |
| `isLastAbort()`                    | Check if last operation was abort   |
| `isLastFinish()`                   | Check if last operation was finish  |
| `lastHistoryContains(String text)` | Check if last message contains text |
| `getAllHistories()`                | Get all history entries             |
| `getHistoryCount()`                | Get total history count             |
| `getStackDepth()`                  | Get current nesting depth           |
| `clear()`                          | Clear all traces (test only)        |

### TraceHistory

| Method                      | Description                    |
| --------------------------- | ------------------------------ |
| `getType()`                 | Get the history type           |
| `getContextName()`          | Get the context name           |
| `getMessage()`              | Get the message                |
| `getTimestamp()`            | Get timestamp (milliseconds)   |
| `getDateTime()`             | Get DateTime object            |
| `isStart()`                 | Check if type is Start         |
| `isLog()`                   | Check if type is Log           |
| `isSkip()`                  | Check if type is Skip          |
| `isAbort()`                 | Check if type is Abort         |
| `isFinish()`                | Check if type is Finish        |
| `containsText(String text)` | Check if message contains text |

### TraceException

| Method                 | Description                             |
| ---------------------- | --------------------------------------- |
| `getCurrentContext()`  | Get current context when error occurred |
| `getExpectedContext()` | Get expected context                    |
| `getOperationType()`   | Get operation type that failed          |

## 🎨 Best Practices

### 1. Always Clear in Tests

```apex
@isTest
static void testSomething() {
  TraceFlow.clear();  // ✅ Always start with clean state
  // ... test code
}
```

### 2. Use Descriptive Context Names

```apex
// ✅ Good
Trace.of('QuoteProcessor.calculateTotals')
Trace.of('AccountBatch.execute.processRecord')

// ❌ Bad
Trace.of('process')
Trace.of('method1')
```

### 3. Include Meaningful Messages

```apex
// ✅ Good - Structured messages
trace.finish('Processed: 10 records, Errors: 0');
trace.skip('Reason: No active accounts found');
trace.abort('Error: Duplicate value on field Email__c');

// ❌ Bad - Vague messages
trace.finish('done');
trace.skip('skipped');
trace.abort('error');
```

### 4. Always Finish Contexts

```apex
// ✅ Good - Always finish in try-finally
Trace trace = Trace.of('MyProcess');
trace.start();
try {
  // process
  trace.finish();
} catch (Exception e) {
  trace.abort(e.getMessage());
  throw e;
}

// ❌ Bad - Missing finish on exception path
Trace trace = Trace.of('MyProcess');
trace.start();
// process - if exception occurs, trace never finishes!
trace.finish();
```

### 5. Use in Constructors

```apex
public class MyService {
  public MyService(Account account) {
    Trace trace = Trace.of('MyService.constructor');
    trace.start();

    if (account == null) {
      trace.skip('Account is null');
      return;
    }

    // initialize
    trace.finish();
  }
}
```

## 🔄 Execution Modes

ApexTrace supports two modes:

### Strict Mode (Default in Tests)

- Throws `TraceException` immediately on context mismatch
- Best for development and testing
- Helps catch logic errors early

```apex
Trace outer = Trace.of('Outer');
outer.start();
Trace inner = Trace.of('Inner');
inner.start();

outer.finish();  // ❌ TraceException: Inner is still active
```

### Relaxed Mode (Default in Production)

- Automatically aborts mismatched contexts
- More forgiving for production environments
- Logs auto-abort events

```apex
TraceFlow.changeModeTo(TraceFlow.TraceMode.Relaxed);

Trace outer = Trace.of('Outer');
outer.start();
Trace inner = Trace.of('Inner');
inner.start();

outer.finish();  // ✅ Auto-aborts Inner, then finishes Outer
```

## 📊 Test Coverage

ApexTrace maintains high test coverage:

| Class          | Coverage |
| -------------- | -------- |
| Trace          | 98%      |
| TraceFlow      | 98%      |
| TraceHistory   | 100%     |
| TraceException | 100%     |

**Total Tests**: 61  
**Pass Rate**: 100%

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/ApexTrace.git

# Deploy to scratch org
sf org create scratch -f config/project-scratch-def.json -a ApexTrace
sf project deploy start -d force-app/main/default/classes/ApexTrace

# Run tests
sf apex run test --class-names TraceTest --class-names TraceFlowTest --class-names TraceExceptionTest --class-names TraceHistoryTest -c -y
```

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

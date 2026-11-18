---
name: apex-trace-testing
description: Apex tests that check the path and the governor usage of code traced with ApexTrace. Use when writing or fixing @IsTest classes in a project that contains Trace.cls, including wrapping a test in Trace.of('Normal: ...') / start / finish as its description, TraceFlow.isLastFinish / isLastSkip / isLastAbort, lastHistoryContains / contains / lastHistory / getAllHistories, TraceFlow.discardArrange at the Arrange / Act boundary, TraceFlow.usageOf / usagesOf / lastUsage, TraceUsage.assertSoqlQueriesAtMost / assertSoqlRowsAtMost / assertDmlStatementsAtMost / assertDmlRowsAtMost / assertCalloutsAtMost / assertInvocationsAtMost with a reason, getSoqlQueries / getInvocations, bulk tests with more than 200 records, Limits read inside Test.startTest / Test.stopTest, errors such as "Usage assertion failed", "Usage assertion ... is unfounded ... (invocations = 0)", "lastUsage() is ambiguous", "discardArrange() must be called at the Arrange / Act boundary", and writing test descriptions in the project's language. Not for editing ApexTrace's own tests.
---

# ApexTrace: Testing with TraceFlow and TraceUsage

`TraceFlow` keeps the history of every Trace call in the transaction. Tests read it to prove which path the code took (`finish`, `skip` or `abort`) and how much each named context consumed (`TraceUsage`). Path checks catch tests that pass without exercising the code: a method that returned early leaves its side-effect assertions with nothing to check, but `isLastFinish()` turns red. Usage checks catch queries or DML that grow with the number of records. For writing the Traces themselves, see `apex-trace-logging`.

## Rules

1. Write test descriptions and assert messages in the language the project's tests already use, and keep its case labels (see "Test descriptions").
2. Wrap each test method in its own Trace: `Trace t = Trace.of('<label>: <description>'); t.start();` first, `t.finish();` last. The text is the test's description.
3. Assert the path (`isLastFinish` / `isLastSkip` / `isLastAbort`) next to the assertions on side effects. Test each path in its own test method.
4. Call `TraceFlow.discardArrange()` at the Arrange / Act boundary, next to `Test.startTest()`.
5. Assert usage with `TraceFlow.usageOf(NAME)` only in tests that run real queries and DML. With mocked data access the usage is zero and every bound passes.
6. Set bounds loosely: a per-record query or DML must fail them, one extra legitimate query must not. Use `AtMost(0)` only when "does nothing" is the claim.
7. Give every usage assertion a reason: the measured value and what a rise would mean.
8. Don't use `TraceFlow.lastUsage()`. Use `usageOf(NAME)`.
9. Use the production class's name constant (`OpportunityLossService.TRACE_NAME`). Don't retype context names.

## Test descriptions

The text passed to `Trace.of(...)` in a test is its human-readable description; the method name stays machine-readable. Don't repeat the description in a comment above the method.

Write test descriptions, comments and assert messages in the language the project's existing tests use. If the project labels test cases, keep its labels and put them first:

| Language | Labels |
|---|---|
| Japanese | `正常系:` / `異常系:` / `エッジケース:` |
| English | `Normal:` / `Error:` / `Edge:` |

Write a full sentence that says what is verified: `Trace.of('Normal: updates the record when the input is valid')`. Follow the project's own naming for test classes and methods. If the project has no tests yet, ask which language to use.

The wrapping Trace also checks the code under test: if the code leaves its own Trace open, the test's `t.finish()` throws "not the current context".

## Example

Production code: `OpportunityLossService` from the `apex-trace-logging` skill.

```apex
@IsTest(SeeAllData=false)
private class OpportunityLossServiceTest {
  @IsTest
  static void closeAsLostClosesOpenOpportunities() {
    Trace t = Trace.of('Normal: closes an open opportunity as lost');
    t.start();

    Account account = new Account(Name = 'Test');
    insert account;
    Opportunity opportunity = new Opportunity(
      AccountId = account.Id, Name = 'Test', StageName = 'Prospecting', CloseDate = Date.today()
    );
    insert opportunity;

    TraceFlow.discardArrange();
    Test.startTest();
    Integer closed = new OpportunityLossService().closeAsLost(new Set<Id>{ opportunity.Id });
    Test.stopTest();

    Assert.areEqual(1, closed, 'Normal: one opportunity is closed.');
    Assert.areEqual(
      'Closed Lost',
      [SELECT StageName FROM Opportunity WHERE Id = :opportunity.Id].StageName,
      'Normal: the stage is Closed Lost.'
    );
    Assert.isTrue(TraceFlow.isLastFinish(), 'Normal: the service finished instead of skipping.');

    t.finish();
  }

  @IsTest
  static void closeAsLostSkipsWithoutIds() {
    Trace t = Trace.of('Edge: skips when no opportunity is given');
    t.start();

    TraceFlow.discardArrange();
    Integer closed = new OpportunityLossService().closeAsLost(new Set<Id>());

    Assert.areEqual(0, closed, 'Edge: nothing is closed.');
    Assert.isTrue(TraceFlow.isLastSkip(), 'Edge: the service skipped.');
    Assert.isTrue(TraceFlow.lastHistoryContains('No opportunity to close'), 'Edge: the skip reason is recorded.');

    t.finish();
  }
}
```

An abort path, when the test can make the code fail (`service` and `opportunityIds` come from the Arrange):

```apex
try {
  service.closeAsLost(opportunityIds);
  Assert.fail('Error: the failure is expected to propagate.');
} catch (DmlException e) {
  Assert.isTrue(TraceFlow.isLastAbort(), 'Error: the service aborted its Trace.');
}
```

## Path checks

| Method (static, on `TraceFlow`) | Returns `true` when |
|---|---|
| `isLastFinish()` / `isLastSkip()` / `isLastAbort()` | the last history entry is that kind |
| `lastHistoryContains(text)` | the last entry's message contains `text` |
| `contains(text)` | any entry's message contains `text` |
| `lastHistory()` | returns the last `TraceHistory`, or `null` |
| `getAllHistories()` | returns a copy of every `TraceHistory` |

- The `isLast*` methods look at the last entry, not at the last closed context. A `log()` after the close, or nothing at all in the Act, changes the answer. That is why `discardArrange()` matters: without it, an Act that traced nothing reads an Arrange entry.
- `lastHistoryContains` fits the reason given to `finish` / `skip` / `abort` just before. To check a `log()` line, or to stay stable when log lines are added, use `contains`.
- Text matching is case-sensitive and `null` text returns `false`.
- Entries are `Start`, `Log`, `Skip`, `Abort`, `Finish`. See [references/history-and-usage.md](references/history-and-usage.md) for `TraceHistory`.

## discardArrange

```apex
insertTestData();             // Arrange: triggers may run traced code here
TraceFlow.discardArrange();   // the history starts again from here
Test.startTest();
// Act
Test.stopTest();
```

- It clears the history only. Open contexts and their usage snapshots stay, so the test's own wrapping Trace still closes normally.
- In tests it throws "discardArrange() must be called at the Arrange / Act boundary, while no usecase context is open. Currently open: N contexts." when more than one context is open.
- Forgetting it is not detected by the library. `assertInvocationsAtMost` usually catches it, because the Arrange runs show up as extra invocations.

## Usage checks

Every context records the governor usage between its `start()` and its close: SOQL queries, SOQL rows, DML statements, DML rows and callouts.

```apex
TraceFlow.usageOf(OpportunityLossService.TRACE_NAME)
  .assertInvocationsAtMost(1, 'Edge: the test calls the service once.')
  .assertSoqlQueriesAtMost(5, 'Edge: measured 1. A rise with the record count means a query per record.')
  .assertDmlStatementsAtMost(3, 'Edge: measured 1. A rise means DML per record.');
```

| Method | Returns |
|---|---|
| `TraceFlow.usageOf(name)` | `TraceUsage`: the sum of every closed context with that name, never `null`. Zero usage and zero invocations when none closed |
| `TraceFlow.usagesOf(name)` | `List<TraceUsage>`: one per closed context, in close order |
| `TraceFlow.lastUsage()` | the usage of the last closed context. Avoid it (see below) |

| Assertion (on `TraceUsage`, each also takes `(Integer max, String reason)`) | Bounds |
|---|---|
| `assertSoqlQueriesAtMost(max)` | SOQL queries |
| `assertSoqlRowsAtMost(max)` | rows returned by SOQL |
| `assertDmlStatementsAtMost(max)` | DML statements |
| `assertDmlRowsAtMost(max)` | rows processed by DML |
| `assertCalloutsAtMost(max)` | callouts |
| `assertInvocationsAtMost(max)` | how many times the named context closed |

- Each assertion returns the same `TraceUsage`, so they chain.
- A failure throws `TraceException`: "Usage assertion failed: SOQL queries is 12, exceeding the allowed maximum of 5." followed by `Reason: ...` and `Actual usage: ...`. It is catchable, so a `catch (Exception e)` around the Act can swallow it. Keep usage assertions outside such blocks.
- A consumption assertion on a name that never closed (`invocations = 0`) throws "Usage assertion on SOQL queries is unfounded...". This catches a misspelled or renamed context name. `assertInvocationsAtMost(0)` is allowed and is the way to assert that a unit does not run.
- `usageOf` reports exclusive usage: each context's own consumption without its direct traced children. Raw values on history entries and `lastUsage()` are inclusive. Details in [references/history-and-usage.md](references/history-and-usage.md).
- Names are compared with Apex `==`, so case is ignored.
- Raw numbers: `getSoqlQueries()`, `getSoqlRows()`, `getDmlStatements()`, `getDmlRows()`, `getCallouts()`, `getInvocations()`, and `format()` for a one-line summary.

### Bulk tests

Per-record queries only show with many records. Insert more than 200 records in one DML so triggers run in more than one chunk, then assert three things:

```apex
Test.startTest();
new OpportunityLossService().closeAsLost(opportunityIds);   // 250 ids
Integer queriesInAct = Limits.getQueries();                  // read inside the block
Test.stopTest();

// 1. The result: fails if any record was dropped
Assert.areEqual(250, [SELECT COUNT() FROM Opportunity WHERE StageName = 'Closed Lost'], 'Edge: all 250 are closed.');
// 2. The unit: wiring (invocations) and content (consumption) on separate lines
TraceFlow.usageOf(OpportunityLossService.TRACE_NAME)
  .assertInvocationsAtMost(1, 'Edge: called once by the test with 250 ids.')
  .assertSoqlQueriesAtMost(5, 'Edge: measured 1. A per-record query would exceed this.');
// 3. The whole transaction
Assert.isTrue(queriesInAct < Limits.getLimitQueries() / 2, 'Edge: SOQL stays under half the limit. Used ' + queriesInAct);
```

- Keep the result assertion. Code that processes only part of the records uses fewer queries, so the usage assertions alone stay green.
- When the unit runs from a trigger, its invocation count depends on the number of records, because triggers run per 200-record chunk. Write the record count in the reason, and update the bound when the count changes.
- Read `Limits` between `Test.startTest()` and `Test.stopTest()`. After `stopTest()` the counters return to their values from before `startTest()`, so an assertion on `Limits` there checks nothing.

### Why not lastUsage

`lastUsage()` returns only the last closed context. When a handler runs several traced units, it returns the last one and misses the rest. In tests it throws "lastUsage() is ambiguous", followed by "N contexts closed at the same level:" and the names separated by ` / `, when two or more contexts closed at the shallowest level; the listed names go straight into `usageOf`. Don't take the last element of `usagesOf(name)` as "the Act" either: it is one invocation, and a second chunk makes it partial.

## Common mistakes

| Symptom | Cause | Fix |
|---|---|---|
| Test is green although the code returned early | Only side effects are asserted, and there were none to check | Add `Assert.isTrue(TraceFlow.isLastFinish(), ...)` |
| `isLastSkip()` is `true` although the Act ran nothing | The history still holds an Arrange entry | Call `TraceFlow.discardArrange()` before the Act |
| `isLastFinish()` is `false` right after a successful call | A `log()` or another context came after the close | Assert right after the call, or use `contains` for the message |
| `assertInvocationsAtMost` fails by one or more | Arrange DML ran the unit through a trigger | `TraceFlow.discardArrange()` at the boundary |
| "Usage assertion ... is unfounded ... (invocations = 0)" | Wrong or renamed context name, or the unit never ran in this test | Use the production name constant; check the test reaches the unit |
| Usage bounds pass whatever the code does | Data access is mocked, so nothing is consumed | Assert usage in a test with real queries and DML |
| Usage bounds pass with a per-record query | Too few records | Insert more than 200 records |
| Usage test fails after a harmless refactor | The bound equals the measured value | Loosen it to a level a per-record pattern still breaks |
| "lastUsage() is ambiguous" | Several contexts closed at the same level | `TraceFlow.usageOf(name)` |
| "discardArrange() must be called at the Arrange / Act boundary..." | A context of the code under test is still open | Call it before the Act, when only the test's own Trace is open |
| Test's own `t.finish()` throws "not the current context" | The code under test left its Trace open | Fix the code: close on every path (`apex-trace-logging`) |
| `Limits.getQueries()` assertion always passes | Read after `Test.stopTest()` | Read it inside the block |

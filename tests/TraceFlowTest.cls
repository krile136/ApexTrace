/**
 * Copyright 2025 Hiroyuki Matsuoka
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * @description Test class for TraceFlow to improve code coverage
 * Tests edge cases and internal methods of TraceFlow
 */
@isTest
public with sharing class TraceFlowTest {
  @isTest
  static void testPush_WhenApplyNull_ThenDoNothing() {
    // Arrange / Act
    TraceFlow.push(null);

    // Assert
    Assert.isTrue(TraceFlow.isEmpty());
  }

  @isTest
  static void testCurrentContextName_WhenEmpty_ThenReturnNull() {
    // Arrange / Act
    String contextName = TraceFlow.currentContextName();

    // Assert
    Assert.isNull(contextName);
  }

  @isTest
  static void testPop_WhenEmpty_ThenDoNothing() {
    // Arrange / Act / Assert
    TraceFlow.pop(); // Should not throw exception
    Assert.isTrue(TraceFlow.isEmpty());
  }

  @isTest
  static void testLastHistory_WhenEmpty_ThenReturnNull() {
    // Arrange / Act
    TraceHistory history = TraceFlow.lastHistory();

    // Assert
    Assert.isNull(history);
  }

  @isTest
  static void testIsLastXXX_WhenEmpty_ThenReturnFalse() {
    // Arrange / Act / Assert
    Assert.isFalse(TraceFlow.isLastStart());
    Assert.isFalse(TraceFlow.isLastLog());
    Assert.isFalse(TraceFlow.isLastSkip());
    Assert.isFalse(TraceFlow.isLastAbort());
    Assert.isFalse(TraceFlow.isLastFinish());
  }

  @isTest
  static void testLastHistoryContains_WhenEmpty_ThenReturnFalse() {
    // Arrange / Act
    Boolean result = TraceFlow.lastHistoryContains('test');

    // Assert
    Assert.isFalse(result);
  }

  @isTest
  static void testContains_WhenTextExistsInEarlierHistory_ThenReturnTrue() {
    // Arrange
    TraceFlow.clear();
    Trace trace = Trace.of('TestContext');
    trace.start();
    trace.log('first log message');
    trace.log('second log message');
    trace.finish('finished');

    // Act / Assert - the matching entry is not the last one
    Assert.isTrue(TraceFlow.contains('first log'));
    Assert.isFalse(TraceFlow.lastHistoryContains('first log'));
  }

  @isTest
  static void testContains_WhenTextDoesNotExist_ThenReturnFalse() {
    // Arrange
    TraceFlow.clear();
    Trace trace = Trace.of('TestContext');
    trace.start();
    trace.log('some log message');
    trace.finish();

    // Act / Assert
    Assert.isFalse(TraceFlow.contains('nonexistent'));
  }

  @isTest
  static void testContains_WhenEmpty_ThenReturnFalse() {
    // Arrange
    TraceFlow.clear();

    // Act / Assert
    Assert.isFalse(TraceFlow.contains('anything'));
  }

  @isTest
  static void testContains_WhenTextIsNull_ThenReturnFalse() {
    // Arrange
    TraceFlow.clear();
    Trace trace = Trace.of('TestContext');
    trace.start();
    trace.finish('finished');

    // Act / Assert
    Assert.isFalse(TraceFlow.contains(null));
  }

  @isTest
  static void testLastUsage_WhenNoContextClosed_ThenReturnNull() {
    // Arrange
    TraceFlow.clear();
    Trace trace = Trace.of('TestContext');
    trace.start();

    // Act / Assert - only a Start entry exists, no context has been closed yet
    Assert.isNull(TraceFlow.lastUsage());
  }

  @isTest
  static void testLastUsage_WhenContextFinished_ThenReturnsConsumption() {
    // Arrange
    TraceFlow.clear();
    Trace trace = Trace.of('TestContext');
    trace.start();
    List<User> users = [SELECT Id FROM User LIMIT 1];
    trace.finish('done');

    // Act
    TraceUsage usage = TraceFlow.lastUsage();

    // Assert
    Assert.isNotNull(usage);
    Assert.areEqual(1, usage.getSoqlQueries());
    Assert.areEqual(0, usage.getDmlStatements());
    Assert.areEqual(usage, TraceFlow.lastHistory().getUsage());
  }

  @isTest
  static void testLastUsage_WhenContextSkipped_ThenUsageIsAttached() {
    // Arrange
    TraceFlow.clear();
    Trace trace = Trace.of('TestContext');
    trace.start();
    trace.skip('nothing to do');

    // Act
    TraceUsage usage = TraceFlow.lastUsage();

    // Assert
    Assert.isNotNull(usage);
    Assert.areEqual(0, usage.getSoqlQueries());
    Assert.areEqual(0, usage.getDmlStatements());
  }

  @isTest
  static void testLastUsage_WhenNested_ThenParentIncludesChildConsumption() {
    // Arrange
    TraceFlow.clear();
    Trace outerTrace = Trace.of('OuterContext');
    outerTrace.start();
    Trace innerTrace = Trace.of('InnerContext');
    innerTrace.start();
    List<User> innerUsers = [SELECT Id FROM User LIMIT 1];
    innerTrace.finish();

    // Act / Assert - innerTrace context consumed 1 SOQL
    Assert.areEqual(1, TraceFlow.lastUsage().getSoqlQueries());

    List<User> outerUsers = [SELECT Id FROM User LIMIT 1];
    outerTrace.finish();

    // Act / Assert - outerTrace includes the nested innerTrace context's consumption
    Assert.areEqual(2, TraceFlow.lastUsage().getSoqlQueries());
  }

  @isTest
  static void testGetUsage_WhenStartOrLogEntry_ThenNull() {
    // Arrange
    TraceFlow.clear();
    Trace trace = Trace.of('TestContext');
    trace.start();
    trace.log('a log message');
    trace.finish();

    // Act
    List<TraceHistory> histories = TraceFlow.getAllHistories();

    // Assert - only the closing entry carries usage
    Assert.isNull(histories[0].getUsage());
    Assert.isNull(histories[1].getUsage());
    Assert.isNotNull(histories[2].getUsage());
  }

  @isTest
  static void testEnsureContext_WhenRelaxedModeAndContextNotFound_ThenThrowException() {
    // Arrange
    TraceFlow.changeModeTo(TraceFlow.TraceMode.Relaxed);
    Trace outerTrace = Trace.of('OuterContext');
    outerTrace.start();
    Trace innerTrace = Trace.of('InnerContext');
    innerTrace.start();

    // Act / Assert
    try {
      // Try to operate on a context that doesn't exist in the stack
      TraceFlow.ensureContext('NonExistentContext', TraceHistory.HistoryType.Log);
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      String expect = 'No matching Trace context found for Log operation in current context: NonExistentContext.';
      Assert.isTrue(e.getMessage().contains(expect));
    }
  }

  @isTest
  static void testChangeModeTo_WhenChangeToStrict_ThenModeIsStrict() {
    // Arrange
    TraceFlow.changeModeTo(TraceFlow.TraceMode.Relaxed);

    // Act
    TraceFlow.changeModeTo(TraceFlow.TraceMode.Strict);
    Trace outerTrace = Trace.of('OuterContext');
    outerTrace.start();
    Trace innerTrace = Trace.of('InnerContext');
    innerTrace.start();

    // Assert - In Strict mode, this should throw exception
    try {
      outerTrace.log('This should fail in strict mode');
      Assert.fail('Exception was not thrown in Strict mode.');
    } catch (TraceException e) {
      String expect = 'The context for Log operation is not the current context.';
      Assert.isTrue(e.getMessage().contains(expect));
    }
  }

  @isTest
  static void testSkipWithReason_WhenApplyCalled_ThenHistoryContainsReason() {
    // Arrange
    Trace trace = Trace.of('TestContext');
    trace.start();

    // Act
    trace.skip('Test reason for skipping');

    // Assert
    Assert.isTrue(TraceFlow.isLastSkip());
    Assert.isTrue(TraceFlow.lastHistoryContains('Test reason for skipping'));
  }

  @isTest
  static void testFinishWithResult_WhenApplyCalled_ThenHistoryContainsResult() {
    // Arrange
    Trace trace = Trace.of('TestContext');
    trace.start();

    // Act
    trace.finish('Test result for finishing');

    // Assert
    Assert.isTrue(TraceFlow.isLastFinish());
    Assert.isTrue(TraceFlow.lastHistoryContains('Test result for finishing'));
  }

  @isTest
  static void testAbortWithReason_WhenApplyCalled_ThenHistoryContainsReason() {
    // Arrange
    Trace trace = Trace.of('TestContext');
    trace.start();

    // Act
    trace.abort('Test reason for aborting');

    // Assert
    Assert.isTrue(TraceFlow.isLastAbort());
    Assert.isTrue(TraceFlow.lastHistoryContains('Test reason for aborting'));
  }

  @isTest
  static void testMultipleNesting_WhenProperlyManaged_ThenNoException() {
    // Arrange
    Trace level1 = Trace.of('Level1');
    level1.start();
    Trace level2 = Trace.of('Level2');
    level2.start();
    Trace level3 = Trace.of('Level3');
    level3.start();

    // Act
    level3.log('Level 3 log');
    level3.finish();
    level2.log('Level 2 log');
    level2.finish();
    level1.log('Level 1 log');
    level1.finish();

    // Assert
    Assert.isTrue(TraceFlow.isLastFinish());
  }

  @isTest
  static void testRelaxedMode_WhenMultipleMismatchedContexts_ThenAutoAbort() {
    // Arrange
    TraceFlow.changeModeTo(TraceFlow.TraceMode.Relaxed);
    Trace level1 = Trace.of('Level1');
    level1.start();
    Trace level2 = Trace.of('Level2');
    level2.start();
    Trace level3 = Trace.of('Level3');
    level3.start();

    // Act - Try to operate on level1 while level3 is current (should auto-abort level3 and level2)
    level1.log('This should auto-abort level3 and level2');

    // Assert
    Assert.isTrue(TraceFlow.isLastLog());
    Assert.isTrue(TraceFlow.lastHistoryContains('This should auto-abort level3 and level2'));
  }

  @isTest
  static void testGetAllHistories_WhenMultipleOperations_ThenReturnsAllHistories() {
    // Arrange
    TraceFlow.clear();
    Trace trace = Trace.of('TestContext');
    trace.start();
    trace.log('Log message 1');
    trace.log('Log message 2');

    // Act
    List<TraceHistory> histories = TraceFlow.getAllHistories();

    // Assert
    Assert.areEqual(3, histories.size());
    Assert.isTrue(histories[0].isStart());
    Assert.isTrue(histories[1].isLog());
    Assert.isTrue(histories[2].isLog());
  }

  @isTest
  static void testGetHistoryCount_WhenOperationsExecuted_ThenReturnsCorrectCount() {
    // Arrange
    TraceFlow.clear();
    Trace trace = Trace.of('TestContext');
    trace.start();
    trace.log('Log message');

    // Act
    Integer count = TraceFlow.getHistoryCount();

    // Assert
    Assert.areEqual(2, count);
  }

  @isTest
  static void testGetStackDepth_WhenNestedTraces_ThenReturnsCorrectDepth() {
    // Arrange
    TraceFlow.clear();
    Trace level1 = Trace.of('Level1');
    level1.start();
    Trace level2 = Trace.of('Level2');
    level2.start();
    Trace level3 = Trace.of('Level3');
    level3.start();

    // Act
    Integer depth = TraceFlow.getStackDepth();

    // Assert
    Assert.areEqual(3, depth);
  }

  @isTest
  static void testClear_WhenCalled_ThenStackAndHistoryAreEmpty() {
    // Arrange
    Trace trace = Trace.of('TestContext');
    trace.start();
    trace.log('Test message');

    // Act
    TraceFlow.clear();

    // Assert
    Assert.isTrue(TraceFlow.isEmpty());
    Assert.areEqual(0, TraceFlow.getHistoryCount());
    Assert.areEqual(0, TraceFlow.getStackDepth());
  }

  @isTest
  static void testGetAllHistories_WhenEmpty_ThenReturnsEmptyList() {
    // Arrange
    TraceFlow.clear();

    // Act
    List<TraceHistory> histories = TraceFlow.getAllHistories();

    // Assert
    Assert.areEqual(0, histories.size());
  }

  @isTest
  static void testGetStackDepth_WhenEmpty_ThenReturnsZero() {
    // Arrange
    TraceFlow.clear();

    // Act
    Integer depth = TraceFlow.getStackDepth();

    // Assert
    Assert.areEqual(0, depth);
  }

  // ===============================================================================
  // usageOf / usagesOf (issue #6): per-context-name aggregation.
  // Consumption sums EXCLUSIVE usage (own minus nested children) so nested
  // re-entries are not double-counted; invocations counts every close.
  // Driven by a stub ILimitsReader — deterministic, no real SOQL/DML.
  // ===============================================================================

  private class StubLimitsReader implements ILimitsReader {
    public Integer queries = 0;
    public Integer queryRows = 0;
    public Integer dmlStatements = 0;
    public Integer dmlRows = 0;
    public Integer callouts = 0;

    public Integer getQueries() {
      return this.queries;
    }
    public Integer getQueryRows() {
      return this.queryRows;
    }
    public Integer getDmlStatements() {
      return this.dmlStatements;
    }
    public Integer getDmlRows() {
      return this.dmlRows;
    }
    public Integer getCallouts() {
      return this.callouts;
    }
  }

  @isTest
  static void testUsageOf_WhenSameNameNested_ThenExclusiveSumAndAllInvocations() {
    // Arrange - A(outerTrace) > A(midTrace) > A(innerTrace), each consuming 3 queries of its own.
    // Inclusive diffs are 9 / 6 / 3 — the naive sum (18) double-counts; the
    // exclusive sum is 9 with 3 invocations.
    TraceFlow.clear();
    StubLimitsReader stub = new StubLimitsReader();
    TraceUsage.limitsReader = stub;

    Trace outerTrace = Trace.of('UsecaseA');
    Trace midTrace = Trace.of('UsecaseA');
    Trace innerTrace = Trace.of('UsecaseA');
    outerTrace.start();
    stub.queries += 3;
    midTrace.start();
    stub.queries += 3;
    innerTrace.start();
    stub.queries += 3;
    innerTrace.finish();
    midTrace.finish();
    outerTrace.finish();

    // Act
    TraceUsage usage = TraceFlow.usageOf('UsecaseA');

    // Assert
    Assert.areEqual(3, usage.getInvocations(), 'Nested re-entries must all be counted.');
    Assert.areEqual(9, usage.getSoqlQueries(), 'Exclusive sum must not double-count nesting.');
  }

  @isTest
  static void testUsageOf_WhenDifferentNameNested_ThenConsumptionAttributedByName() {
    // Arrange - A consumes 2 of its own; B (nested in A) consumes 5
    TraceFlow.clear();
    StubLimitsReader stub = new StubLimitsReader();
    TraceUsage.limitsReader = stub;

    Trace a = Trace.of('UsecaseA');
    Trace b = Trace.of('UsecaseB');
    a.start();
    stub.queries += 2;
    b.start();
    stub.queries += 5;
    b.finish();
    a.finish();

    // Assert - B's consumption belongs to B, not to A (A inclusive would be 7)
    Assert.areEqual(2, TraceFlow.usageOf('UsecaseA').getSoqlQueries());
    Assert.areEqual(5, TraceFlow.usageOf('UsecaseB').getSoqlQueries());
    Assert.areEqual(1, TraceFlow.usageOf('UsecaseA').getInvocations());
  }

  @isTest
  static void testUsageOf_WhenNoMatch_ThenZeroObjectAndConsumptionAssertsRejected() {
    // Arrange
    TraceFlow.clear();

    // Act
    TraceUsage usage = TraceFlow.usageOf('NeverRan');

    // Assert - zero object, never null; asserting the context does not run is legitimate
    Assert.areEqual(0, usage.getInvocations());
    Assert.areEqual(0, usage.getSoqlQueries());
    usage.assertInvocationsAtMost(0);

    // Assert - a consumption assert on a context that never ran is unfounded:
    // it would pass vacuously (typo'd name / wrong test layer / missing wiring)
    try {
      usage.assertSoqlQueriesAtMost(5);
      Assert.fail('Expected TraceException to be thrown');
    } catch (TraceException e) {
      Assert.isTrue(e.getMessage().contains('invocations = 0'), e.getMessage());
      Assert.isTrue(e.getMessage().contains('assertInvocationsAtMost(0)'), 'Must guide the not-run assertion: ' + e.getMessage());
    }
  }

  @isTest
  static void testUsageOf_WhenNested_ThenLastUsageStillReturnsOuterInclusive() {
    // Arrange - backward compatibility: lastUsage() keeps returning the most
    // recently closed context's INCLUSIVE usage (outerTrace includes the child)
    TraceFlow.clear();
    StubLimitsReader stub = new StubLimitsReader();
    TraceUsage.limitsReader = stub;

    Trace outerTrace = Trace.of('UsecaseA');
    Trace innerTrace = Trace.of('UsecaseA');
    outerTrace.start();
    stub.queries += 3;
    innerTrace.start();
    stub.queries += 3;
    innerTrace.finish();
    outerTrace.finish();

    // Assert
    Assert.areEqual(6, TraceFlow.lastUsage().getSoqlQueries(), 'lastUsage stays inclusive.');
    Assert.areEqual(1, TraceFlow.lastUsage().getInvocations(), 'A single section reports 1.');
  }

  @isTest
  static void testUsagesOf_WhenNested_ThenPerInvocationBreakdownMatchesInvocations() {
    // Arrange - same shape as the exclusive-sum test
    TraceFlow.clear();
    StubLimitsReader stub = new StubLimitsReader();
    TraceUsage.limitsReader = stub;

    Trace outerTrace = Trace.of('UsecaseA');
    Trace innerTrace = Trace.of('UsecaseA');
    outerTrace.start();
    stub.queries += 4;
    innerTrace.start();
    stub.queries += 3;
    innerTrace.finish();
    outerTrace.finish();

    // Act
    List<TraceUsage> usages = TraceFlow.usagesOf('UsecaseA');

    // Assert - innermost closes first; each entry is exclusive with invocations 1
    Assert.areEqual(TraceFlow.usageOf('UsecaseA').getInvocations(), usages.size());
    Assert.areEqual(3, usages[0].getSoqlQueries(), 'Inner exclusive.');
    Assert.areEqual(4, usages[1].getSoqlQueries(), 'Outer exclusive (child subtracted).');
    Assert.areEqual(1, usages[0].getInvocations());
  }

  @isTest
  static void testUsageOf_WhenContextNeverClosed_ThenNotCountedAndNoCrash() {
    // Arrange - the outerTrace context never closes (as after an unwinding exception);
    // only the closed innerTrace invocation is measurable
    TraceFlow.clear();
    StubLimitsReader stub = new StubLimitsReader();
    TraceUsage.limitsReader = stub;

    Trace outerTrace = Trace.of('UsecaseA');
    Trace innerTrace = Trace.of('UsecaseA');
    outerTrace.start();
    stub.queries += 2;
    innerTrace.start();
    stub.queries += 3;
    innerTrace.finish();
    // outerTrace is left open on purpose

    // Act
    TraceUsage usage = TraceFlow.usageOf('UsecaseA');

    // Assert
    Assert.areEqual(1, usage.getInvocations(), 'Unclosed contexts recorded no usage and are not counted.');
    Assert.areEqual(3, usage.getSoqlQueries());
    TraceFlow.clear(); // do not leak the open context into other tests
  }

  @isTest
  static void testAssertInvocationsAtMost_WhenExceeded_ThenThrowWithBreakdown() {
    // Arrange
    TraceFlow.clear();
    StubLimitsReader stub = new StubLimitsReader();
    TraceUsage.limitsReader = stub;

    Trace first = Trace.of('UsecaseA');
    first.start();
    first.finish();
    Trace second = Trace.of('UsecaseA');
    second.start();
    second.finish();

    // Act & Assert
    try {
      TraceFlow.usageOf('UsecaseA').assertInvocationsAtMost(1);
      Assert.fail('Expected TraceException to be thrown');
    } catch (TraceException e) {
      Assert.isTrue(e.getMessage().contains('Invocations'), e.getMessage());
      Assert.isTrue(e.getMessage().contains('2'), 'Message must carry the actual count: ' + e.getMessage());
    }
  }

  // ===============================================================================
  // lastUsage() ambiguity guard + assert reason overloads (issue #8)
  // ===============================================================================

  @isTest
  static void testLastUsage_WhenSeveralContextsCloseAtSameLevel_ThenThrowAmbiguous() {
    // Arrange - the trigger-handler shape: the test's own trace stays open while
    // three usecases open and close at the same level
    TraceFlow.clear();
    Trace outerTrace = Trace.of('TestWrapper');
    outerTrace.start();
    Trace u1 = Trace.of('UsecaseA');
    u1.start();
    u1.finish();
    Trace u2 = Trace.of('UsecaseB');
    u2.start();
    u2.finish();
    Trace u3 = Trace.of('UsecaseC');
    u3.start();
    u3.finish();

    // Act & Assert - Strict (test execution) rejects the ambiguous read and
    // lists the candidates for a copy-paste into usageOf()
    try {
      TraceFlow.lastUsage();
      Assert.fail('Expected TraceException to be thrown');
    } catch (TraceException e) {
      Assert.isTrue(e.getMessage().contains('ambiguous'), e.getMessage());
      Assert.isTrue(e.getMessage().contains('UsecaseA'), e.getMessage());
      Assert.isTrue(e.getMessage().contains('UsecaseC'), e.getMessage());
      Assert.isTrue(e.getMessage().contains('usageOf'), 'Must guide to usageOf: ' + e.getMessage());
    }
    TraceFlow.clear(); // do not leak the open wrapper into other tests
  }

  @isTest
  static void testLastUsage_WhenNestedOnly_ThenNotAmbiguous() {
    // Arrange - A calls B: two contexts close, but nesting is not ambiguity —
    // the outermost close (A) is the natural target
    TraceFlow.clear();
    Trace a = Trace.of('UsecaseA');
    a.start();
    Trace b = Trace.of('UsecaseB');
    b.start();
    b.finish();
    a.finish();

    // Act & Assert - no exception, and lastUsage is A's (inclusive) usage
    Assert.areEqual(TraceFlow.usageOf('UsecaseB').getSoqlQueries(), 0);
    Assert.isNotNull(TraceFlow.lastUsage());
  }

  @isTest
  static void testLastUsage_WhenAmbiguousInRelaxedMode_ThenNoException() {
    // Arrange - production never throws from this guard
    TraceFlow.clear();
    TraceFlow.changeModeTo(TraceFlow.TraceMode.Relaxed);
    Trace u1 = Trace.of('UsecaseA');
    u1.start();
    u1.finish();
    Trace u2 = Trace.of('UsecaseB');
    u2.start();
    u2.finish();

    // Act & Assert
    Assert.isNotNull(TraceFlow.lastUsage());
    TraceFlow.changeModeTo(TraceFlow.TraceMode.Strict);
  }

  @isTest
  static void testAssertReason_WhenExceeded_ThenReasonPrintedBeforeNumbers() {
    // Arrange
    TraceFlow.clear();
    StubLimitsReader stub = new StubLimitsReader();
    TraceUsage.limitsReader = stub;
    Trace tr = Trace.of('UsecaseA');
    tr.start();
    stub.queries += 3;
    tr.finish();

    // Act & Assert
    try {
      TraceFlow.usageOf('UsecaseA').assertSoqlQueriesAtMost(1, '201件insert時の実測は5。増えた場合は配線が増えた可能性があります');
      Assert.fail('Expected TraceException to be thrown');
    } catch (TraceException e) {
      String msg = e.getMessage();
      Assert.isTrue(msg.contains('Reason: 201件insert時の実測は5'), msg);
      Assert.isTrue(
        msg.indexOf('Reason:') < msg.indexOf('Actual usage:'),
        'The reason must come before the numbers: ' + msg
      );
    }
  }

  @isTest
  static void testAssertReason_WhenNullReason_ThenMessageUnchanged() {
    // Arrange - the 1-arg asserts delegate with a null reason: no Reason line
    TraceFlow.clear();
    StubLimitsReader stub = new StubLimitsReader();
    TraceUsage.limitsReader = stub;
    Trace tr = Trace.of('UsecaseA');
    tr.start();
    stub.queries += 3;
    tr.finish();

    // Act & Assert
    try {
      TraceFlow.usageOf('UsecaseA').assertSoqlQueriesAtMost(1);
      Assert.fail('Expected TraceException to be thrown');
    } catch (TraceException e) {
      Assert.isFalse(e.getMessage().contains('Reason:'), e.getMessage());
    }
  }

  @isTest
  static void testGetAllHistories_StaysPublicForTelemetry() {
    // Arrange - regression guard: getAllHistories() is the only production
    // entry point for telemetry (enumerating every context of a transaction);
    // this call compiling and returning is the assertion
    TraceFlow.clear();
    Trace tr = Trace.of('UsecaseA');
    tr.start();
    tr.finish();

    // Act & Assert
    Assert.areEqual(2, TraceFlow.getAllHistories().size(), 'Start + Finish entries.');
  }

  // ===============================================================================
  // discardArrange (issue #10): align the observation window with the Act phase.
  // Only the history is discarded; the open stack and snapshots survive.
  // ===============================================================================

  @isTest
  static void testDiscardArrange_WhenArrangeTraced_ThenUsageOfSeesOnlyAct() {
    // Arrange - a usecase runs once during Arrange (e.g. via a trigger), then twice in Act
    TraceFlow.clear();
    StubLimitsReader stub = new StubLimitsReader();
    TraceUsage.limitsReader = stub;

    Trace arrangeRun = Trace.of('UsecaseA');
    arrangeRun.start();
    stub.queries += 5;
    arrangeRun.finish();

    TraceFlow.discardArrange();

    Trace actRun1 = Trace.of('UsecaseA');
    actRun1.start();
    stub.queries += 2;
    actRun1.finish();
    Trace actRun2 = Trace.of('UsecaseA');
    actRun2.start();
    stub.queries += 2;
    actRun2.finish();

    // Act
    TraceUsage usage = TraceFlow.usageOf('UsecaseA');

    // Assert - the Arrange invocation and its 5 queries are gone
    Assert.areEqual(2, usage.getInvocations(), 'Only the Act invocations count.');
    Assert.areEqual(4, usage.getSoqlQueries(), 'Only the Act consumption counts.');
  }

  @isTest
  static void testDiscardArrange_WhenWrappingTraceOpen_ThenItStillFinishes() {
    // Arrange - the essential guarantee: the test-authoring convention wraps the
    // whole test in a Trace; discarding at the boundary must not break its close
    TraceFlow.clear();
    Trace wrapper = Trace.of('テストの説明');
    wrapper.start();

    Trace arrangeRun = Trace.of('UsecaseA');
    arrangeRun.start();
    arrangeRun.finish();

    TraceFlow.discardArrange();

    Trace actRun = Trace.of('UsecaseA');
    actRun.start();
    actRun.finish();

    wrapper.finish(); // must not throw: traces / startSnapshots were left intact

    // Assert - the wrapper closed normally and is the last history entry
    Assert.isTrue(TraceFlow.isLastFinish());
    Assert.areEqual(0, TraceFlow.getStackDepth(), 'The stack unwound completely.');
  }

  @isTest
  static void testDiscardArrange_WhenActProducesNothing_ThenPathAssertsAreActScoped() {
    // Arrange - an Arrange context finished; after the boundary the Act usecase skips
    TraceFlow.clear();
    Trace arrangeRun = Trace.of('ArrangeUsecase');
    arrangeRun.start();
    arrangeRun.finish();

    TraceFlow.discardArrange();

    Trace actRun = Trace.of('ActUsecase');
    actRun.start();
    actRun.skip('nothing to do');

    // Assert - isLastSkip reads the Act path, not the Arrange finish
    Assert.isTrue(TraceFlow.isLastSkip());
    Assert.isFalse(TraceFlow.contains('ArrangeUsecase'), 'Arrange history is gone.');
  }

  @isTest
  static void testDiscardArrange_WhenNothingAccumulated_ThenIdempotent() {
    // Arrange
    TraceFlow.clear();

    // Act - empty, then twice in a row: neither may throw
    TraceFlow.discardArrange();
    TraceFlow.discardArrange();

    // Assert
    Assert.areEqual(0, TraceFlow.getHistoryCount());
  }

  @isTest
  static void testDiscardArrange_WhenUsecaseContextOpen_ThenThrowInStrict() {
    // Arrange - calling mid-context would silently drop the open context from
    // usagesOf (its Start is erased); Strict rejects the misplacement
    TraceFlow.clear();
    Trace wrapper = Trace.of('テストの説明');
    wrapper.start();
    Trace usecase = Trace.of('UsecaseA');
    usecase.start();

    // Act & Assert
    try {
      TraceFlow.discardArrange();
      Assert.fail('Expected TraceException to be thrown');
    } catch (TraceException e) {
      Assert.isTrue(e.getMessage().contains('Arrange / Act boundary'), e.getMessage());
    }
    TraceFlow.clear(); // unwind the open contexts
  }

  @isTest
  static void testDiscardArrange_WhenRelaxedMode_ThenGuardInactive() {
    // Arrange - production never throws from this guard
    TraceFlow.clear();
    TraceFlow.changeModeTo(TraceFlow.TraceMode.Relaxed);
    Trace wrapper = Trace.of('Outer');
    wrapper.start();
    Trace usecase = Trace.of('UsecaseA');
    usecase.start();

    // Act - no exception even though two contexts are open
    TraceFlow.discardArrange();

    // Assert
    Assert.areEqual(0, TraceFlow.getHistoryCount());
    TraceFlow.changeModeTo(TraceFlow.TraceMode.Strict);
    TraceFlow.clear();
  }
}

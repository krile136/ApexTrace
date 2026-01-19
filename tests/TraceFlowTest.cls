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
  static void testGetLastHistory_WhenEmpty_ThenReturnNull() {
    // Arrange
    TraceFlow flow = new TraceFlow();

    // Act
    TraceHistory history = flow.getLastHistory();

    // Assert
    Assert.isNull(history);
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
}

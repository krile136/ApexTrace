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
 * @description Test class for Trace, TraceFlow, and TraceHistory
 * Tests the context management, nesting, error handling, and various trace operations
 */
@isTest
public with sharing class TraceTest {
  @isTest
  static void testOf_WhenApplyNull_ThenThrowException() {
    // Arrange / Act / Assert
    try {
      Trace.of(null);
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      String expect = 'Context name is null.';
      Assert.areEqual(expect, e.getMessage());
    }
  }

  @isTest
  static void testOf_WhenApplyEmptyString_ThenThrowException() {
    // Arrange / Act / Assert
    try {
      Trace.of('');
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      String expect = 'Context name is empty.';
      Assert.areEqual(expect, e.getMessage());
    }
  }

  @isTest
  static void testLog_WhenExecuteBeforeStart_ThenThrowException() {
    // Arrange
    Trace trace = Trace.of('TestContext');

    // Act / Assert
    try {
      trace.log('This is a test log message.');
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      String expect = 'Trace context is undefined. Please execute the start method of the Trace instance.';
      Assert.areEqual(expect, e.getMessage());
    }
  }

  @isTest
  static void testLog_WhenApplyNull_ThenThrowException() {
    // Arrange
    Trace trace = Trace.of('TestContext');
    trace.start();

    // Act / Assert
    try {
      trace.log(null);
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      String expect = 'Log message is null.';
      Assert.areEqual(expect, e.getMessage());
    }
  }

  @isTest
  static void testLog_WhenApplyEmptyString_ThenThrowException() {
    // Arrange
    Trace trace = Trace.of('TestContext');
    trace.start();

    // Act / Assert
    try {
      trace.log('');
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      String expect = 'Log message is empty.';
      Assert.areEqual(expect, e.getMessage());
    }
  }

  @isTest
  static void testStartToFinish_WhenApplyValidContextName_ThenNoException() {
    // Arrange / Act / Assert
    Trace trace = Trace.of('ValidContext');
    trace.start();
    Assert.isTrue(TraceFlow.isLastStart());

    trace.log('This is a valid log message.');
    Assert.isTrue(TraceFlow.isLastLog());

    trace.finish();
    Assert.isTrue(TraceFlow.isLastFinish());
  }

  @isTest
  static void testLog_WhenApplyNestedTrace_ThenNoException() {
    // Arrange
    Trace outerTrace = Trace.of('OuterContext');
    outerTrace.start();
    Trace innerTrace = Trace.of('InnerContext');
    innerTrace.start();

    // Act
    innerTrace.log('This is a log message in the inner context.');
    innerTrace.finish();
    outerTrace.log('This is a log message in the outer context.');
    outerTrace.finish();

    // Assert
    Assert.isTrue(TraceFlow.isLastFinish());
  }

  @isTest
  static void testFinishAndSkip_WhenApplyNestedTrace_ThenNoException() {
    // Arrange
    Trace outerTrace = Trace.of('OuterContext');
    outerTrace.start();
    Trace innerTrace = Trace.of('InnerContext');
    innerTrace.start();

    // Act
    innerTrace.log('This is a log message in the inner context.');
    innerTrace.finish();
    outerTrace.log('This is a log message in the outer context.');
    outerTrace.skip();

    // Assert
    Assert.isTrue(TraceFlow.isLastSkip());
  }

  @isTest
  static void testLog_WhenOuterLogBeforeInnerFinish_ThenThrowException() {
    // Arrange
    Trace outerTrace = Trace.of('OuterContext');
    outerTrace.start();
    Trace innerTrace = Trace.of('InnerContext');
    innerTrace.start();

    // Act / Assert
    try {
      outerTrace.log('This is a log message in the outer context.');
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      String expect = 'The context for Log operation is not the current context.';
      Assert.isTrue(e.getMessage().contains(expect));
    }
  }

  @isTest
  static void testFinish_WhenOuterFinishBeforeInnerFinish_ThenThrowException() {
    // Arrange
    Trace outerTrace = Trace.of('OuterContext');
    outerTrace.start();
    Trace innerTrace = Trace.of('InnerContext');
    innerTrace.start();

    // Act / Assert
    try {
      outerTrace.finish();
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      String expect = 'The context for Finish operation is not the current context.';
      Assert.isTrue(e.getMessage().contains(expect));
    }
  }

  @isTest
  static void testThrowError_WhenThrowErrorBeforeFinish_ThenOuterLogThrowException() {
    // Arrange
    Trace outerTrace = Trace.of('OuterContext');
    outerTrace.start();
    try {
      try {
        Trace innerTrace = Trace.of('InnerContext');
        innerTrace.start();
        innerTrace.log('This is a log message in the inner context.');
        // Simulate an error occurring in the inner trace
        throw new TraceException('Simulated error in inner trace.');
      } catch (Exception e) {
        // Handle the error and ensure outer trace can still log
        outerTrace.log('This is a log message in the outer context after inner error.');
        outerTrace.finish();
      }
    } catch (TraceException ex) {
      // Assert
      String expect = String.format(
        'The context for {0} operation is not the current context.\n Context for {0} operation: {1}\n Current context: {2}',
        new List<String>{ TraceHistory.HistoryType.Log.name(), 'OuterContext', 'InnerContext' }
      );
      Assert.areEqual(expect, ex.getMessage());
    }
  }

  @isTest
  static void testThrowErrow_WhenThrowErrorBeforeFinishInRelaxedMode_ThenOuterLogNotThrowException() {
    // Arrange
    TraceFlow.changeModeTo(TraceFlow.TraceMode.Relaxed); // Change to Relaxed mode as production
    Trace outerTrace = Trace.of('OuterContext');
    outerTrace.start();
    try {
      try {
        Trace innerTrace = Trace.of('InnerContext');
        innerTrace.start();
        innerTrace.log('This is a log message in the inner context.');
        // Simulate an error occurring in the inner trace
        throw new TraceException('Simulated error in inner trace.');
      } catch (Exception e) {
        // Handle the error and ensure outer trace can still log
        outerTrace.log('This is a log message in the outer context after inner error.');
        outerTrace.finish();
      }
      Assert.isTrue(TraceFlow.isLastFinish());
    } catch (TraceException ex) {
      // Assert
      Assert.fail('Exception was thrown: ' + ex.getMessage());
    }
  }

  @isTest
  static void testThrowError_WhenThrowErrorInNestedTryCatch_ThenOuterLogThrowException() {
    // Arrange
    Trace outerTrace = Trace.of('OuterContext');
    outerTrace.start();
    try {
      try {
        Trace innerTrace = Trace.of('InnerContext');
        innerTrace.start();
        innerTrace.log('This is a log message in the inner context.');
        try {
          Trace innermostTrace = Trace.of('InnermostContext');
          innermostTrace.start();
          innermostTrace.log('This is a log message in the innermost context.');
          // Simulate an error occurring in the innermost trace
          throw new TraceException('Simulated error in innermost trace.');
        } catch (Exception ex) {
          // Handle innermost error
          innerTrace.log('Caught an error in innermost context: ' + ex.getMessage());
          throw ex;
        }
      } catch (Exception e) {
        // Handle the error and ensure outer trace can still log
        outerTrace.log('This is a log message in the outer context after inner error.');
        outerTrace.finish();
      }
    } catch (TraceException ex) {
      // Assert
      String expect = String.format(
        'The context for {0} operation is not the current context.\n Context for {0} operation: {1}\n Current context: {2}',
        new List<String>{ TraceHistory.HistoryType.Log.name(), 'OuterContext', 'InnermostContext' }
      );
      Assert.areEqual(expect, ex.getMessage());
    }
  }

  @isTest
  static void testThrowError_WhenThrowErrorInNestedTryCatchInRelaxedMode_ThenOuterLogNotThrowException() {
    // Arrange
    TraceFlow.changeModeTo(TraceFlow.TraceMode.Relaxed); // Change to Relaxed mode as production
    Trace outerTrace = Trace.of('OuterContext');
    outerTrace.start();
    try {
      try {
        Trace innerTrace = Trace.of('InnerContext');
        innerTrace.start();
        innerTrace.log('This is a log message in the inner context.');
        try {
          Trace innermostTrace = Trace.of('InnermostContext');
          innermostTrace.start();
          innermostTrace.log('This is a log message in the innermost context.');
          // Simulate an error occurring in the innermost trace
          throw new TraceException('Simulated error in innermost trace.');
        } catch (Exception ex) {
          // Handle innermost error
          innerTrace.log('Caught an error in innermost context: ' + ex.getMessage());
          throw ex;
        }
      } catch (Exception e) {
        // Handle the error and ensure outer trace can still log
        outerTrace.log('This is a log message in the outer context after inner error.');
        outerTrace.finish();
        Assert.isTrue(TraceFlow.isLastFinish());
      }
    } catch (TraceException ex) {
      // Assert
      Assert.fail('Exception was thrown: ' + ex.getMessage());
    }
  }

  @isTest
  static void testSkip_WhenExecuteBEforeStart_ThenThrowException() {
    // Arrange
    Trace trace = Trace.of('TestContext');

    // Act / Assert
    try {
      trace.skip();
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      String expect = 'Trace context is undefined. Please execute the start method of the Trace instance.';
      Assert.areEqual(expect, e.getMessage());
    }
  }

  @isTest
  static void testSkip_WhenExecuteAfterStart_ThenNoException() {
    // Arrange
    Trace trace = Trace.of('TestContext');
    trace.start();

    // Act
    trace.skip();

    // Assert
    Assert.isTrue(TraceFlow.isLastSkip());
  }

  @isTest
  static void testSkpiWithMessage_WhenExecuteBeforeStart_ThenThrowException() {
    // Arrange
    Trace trace = Trace.of('TestContext');

    // Act / Assert

    try {
      trace.skip();
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      String expect = 'Trace context is undefined. Please execute the start method of the Trace instance.';
      Assert.areEqual(expect, e.getMessage());
    }
  }

  @isTest
  static void testSkipWithMessage_WhenExecuteAfterStart_ThenNoException() {
    // Arrange
    Trace trace = Trace.of('TestContext');
    trace.start();

    // Act
    trace.skip('Skipping this trace for testing purposes.');

    // Assert
    Assert.isTrue(TraceFlow.isLastSkip());
    Assert.isTrue(TraceFlow.lastHistoryContains('Skipping this trace for testing purposes.'));
  }

  @isTest
  static void testFinish_WhenExecuteBeforeStart_ThenThrowException() {
    // Arrange
    Trace trace = Trace.of('TestContext');
    // Act / Assert
    try {
      trace.finish();
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      String expect = 'Trace context is undefined. Please execute the start method of the Trace instance.';
      Assert.areEqual(expect, e.getMessage());
    }
  }

  @isTest
  static void testFinish_WhenExecuteAfterStart_ThenNoException() {
    // Arrange
    Trace trace = Trace.of('TestContext');
    trace.start();

    // Act
    trace.finish();

    // Assert
    Assert.isTrue(TraceFlow.isLastFinish());
  }

  @isTest
  static void testFinishWithMessage_WhenExecuteBeforeStart_ThenThrowException() {
    // Arrange
    Trace trace = Trace.of('TestContext');
    // Act / Assert
    try {
      trace.finish('Finishing this trace for testing purposes.');
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      String expect = 'Trace context is undefined. Please execute the start method of the Trace instance.';
      Assert.areEqual(expect, e.getMessage());
    }
  }

  @isTest
  static void testFinishWithMessage_WhenExecuteAfterStart_ThenNoException() {
    // Arrange
    Trace trace = Trace.of('TestContext');
    trace.start();

    // Act
    trace.finish('Finishing this trace for testing purposes.');

    // Assert
    Assert.isTrue(TraceFlow.isLastFinish());
    Assert.isTrue(TraceFlow.lastHistoryContains('Finishing this trace for testing purposes.'));
  }

  @isTest
  static void testAbort_WhenExecuteBeforeStart_ThenThrowException() {
    // Arrange
    Trace trace = Trace.of('TestContext');

    // Act / Assert
    try {
      trace.abort();
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      String expect = 'Trace context is undefined. Please execute the start method of the Trace instance.';
      Assert.areEqual(expect, e.getMessage());
    }
  }

  @isTest
  static void testAbort_WhenExecuteAfterStart_ThenNoException() {
    // Arrange
    Trace trace = Trace.of('TestContext');
    trace.start();

    // Act
    trace.abort();

    // Assert
    Assert.isTrue(TraceFlow.isLastAbort());
  }

  @isTest
  static void testAbortWithMessage_WhenExecuteBeforeStart_ThenThrowException() {
    // Arrange
    Trace trace = Trace.of('TestContext');

    // Act / Assert
    try {
      trace.abort('Aborting this trace for testing purposes.');
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      String expect = 'Trace context is undefined. Please execute the start method of the Trace instance.';
      Assert.areEqual(expect, e.getMessage());
    }
  }

  @isTest
  static void testAbortWithMessage_WhenExecuteAfterStart_ThenNoException() {
    // Arrange
    Trace trace = Trace.of('TestContext');
    trace.start();

    // Act
    trace.abort('Aborting this trace for testing purposes.');

    // Assert
    Assert.isTrue(TraceFlow.isLastAbort());
    Assert.isTrue(TraceFlow.lastHistoryContains('Aborting this trace for testing purposes.'));
  }
}

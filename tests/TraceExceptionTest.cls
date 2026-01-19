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
 * @description Test class for TraceException
 * Tests the enhanced exception functionality with context information
 */
@isTest
public with sharing class TraceExceptionTest {
  @isTest
  static void testSetCurrentContext_WhenCalled_ThenContextIsSet() {
    // Arrange
    TraceException ex = new TraceException('Test exception');

    // Act
    ex.setCurrentContext('TestContext');

    // Assert
    Assert.areEqual('TestContext', ex.getCurrentContext());
  }

  @isTest
  static void testSetExpectedContext_WhenCalled_ThenContextIsSet() {
    // Arrange
    TraceException ex = new TraceException('Test exception');

    // Act
    ex.setExpectedContext('ExpectedContext');

    // Assert
    Assert.areEqual('ExpectedContext', ex.getExpectedContext());
  }

  @isTest
  static void testSetOperationType_WhenCalled_ThenTypeIsSet() {
    // Arrange
    TraceException ex = new TraceException('Test exception');

    // Act
    ex.setOperationType('Log');

    // Assert
    Assert.areEqual('Log', ex.getOperationType());
  }

  @isTest
  static void testMethodChaining_WhenCalled_ThenAllPropertiesAreSet() {
    // Arrange / Act
    TraceException ex = new TraceException('Test exception')
      .setCurrentContext('CurrentContext')
      .setExpectedContext('ExpectedContext')
      .setOperationType('Finish');

    // Assert
    Assert.areEqual('CurrentContext', ex.getCurrentContext());
    Assert.areEqual('ExpectedContext', ex.getExpectedContext());
    Assert.areEqual('Finish', ex.getOperationType());
  }

  @isTest
  static void testGetters_WhenNotSet_ThenReturnNull() {
    // Arrange
    TraceException ex = new TraceException('Test exception');

    // Act / Assert
    Assert.isNull(ex.getCurrentContext());
    Assert.isNull(ex.getExpectedContext());
    Assert.isNull(ex.getOperationType());
  }

  @isTest
  static void testException_WhenThrownWithContext_ThenContextIsPreserved() {
    // Arrange
    Trace outerTrace = Trace.of('OuterContext');
    outerTrace.start();
    Trace innerTrace = Trace.of('InnerContext');
    innerTrace.start();

    // Act / Assert
    try {
      outerTrace.finish(); // This should fail because inner is still active
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      // Verify that context information was captured
      Assert.areEqual('OuterContext', e.getExpectedContext());
      Assert.areEqual('InnerContext', e.getCurrentContext());
      Assert.areEqual('Finish', e.getOperationType());
    }
  }

  @isTest
  static void testException_WhenContextMismatchInLog_ThenContextIsPreserved() {
    // Arrange
    Trace outerTrace = Trace.of('OuterContext');
    outerTrace.start();
    Trace innerTrace = Trace.of('InnerContext');
    innerTrace.start();

    // Act / Assert
    try {
      outerTrace.log('This should fail');
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      // Verify that context information was captured
      Assert.areEqual('OuterContext', e.getExpectedContext());
      Assert.areEqual('InnerContext', e.getCurrentContext());
      Assert.areEqual('Log', e.getOperationType());
    }
  }

  @isTest
  static void testException_WhenRelaxedModeAndContextNotFound_ThenHasOperationType() {
    // Arrange
    TraceFlow.changeModeTo(TraceFlow.TraceMode.Relaxed);
    Trace outerTrace = Trace.of('OuterContext');
    outerTrace.start();

    // Act / Assert
    try {
      TraceFlow.ensureContext('NonExistentContext', TraceHistory.HistoryType.Skip);
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      // Verify that operation type was captured
      Assert.areEqual('NonExistentContext', e.getExpectedContext());
      Assert.areEqual('Skip', e.getOperationType());
      Assert.isNull(e.getCurrentContext()); // Current context is cleared in Relaxed mode
    }
  }
}

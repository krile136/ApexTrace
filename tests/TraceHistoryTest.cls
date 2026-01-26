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
 * @description Test class for TraceHistory
 * Tests the getter methods and history entry functionality
 */
@isTest
public with sharing class TraceHistoryTest {
  @isTest
  static void testConstructor_WhenCalled_ThenPropertiesAreSet() {
    // Arrange / Act
    TraceHistory history = new TraceHistory(TraceHistory.HistoryType.Log, 'TestContext', 'Test message');

    // Assert
    Assert.areEqual(TraceHistory.HistoryType.Log, history.getType());
    Assert.areEqual('TestContext', history.getContextName());
    Assert.areEqual('Test message', history.getMessage());
    Assert.isNotNull(history.getTimestamp());
    Assert.isNotNull(history.getDateTime());
  }

  @isTest
  static void testConstructor_WhenNullMessage_ThenMessageIsNull() {
    // Arrange / Act
    TraceHistory history = new TraceHistory(TraceHistory.HistoryType.Start, 'TestContext', null);

    // Assert
    Assert.areEqual(TraceHistory.HistoryType.Start, history.getType());
    Assert.areEqual('TestContext', history.getContextName());
    Assert.isNull(history.getMessage());
  }

  @isTest
  static void testGetDateTime_WhenCalled_ThenReturnsCorrectDateTime() {
    // Arrange
    Long beforeTimestamp = DateTime.now().getTime();
    TraceHistory history = new TraceHistory(TraceHistory.HistoryType.Finish, 'TestContext', 'Test result');
    Long afterTimestamp = DateTime.now().getTime();

    // Act
    DateTime dt = history.getDateTime();
    Long timestamp = history.getTimestamp();

    // Assert
    Assert.isTrue(timestamp >= beforeTimestamp && timestamp <= afterTimestamp);
    Assert.areEqual(timestamp, dt.getTime());
  }

  @isTest
  static void testIsXXX_WhenMatchingType_ThenReturnTrue() {
    // Arrange
    TraceHistory startHistory = new TraceHistory(TraceHistory.HistoryType.Start, 'Test', null);
    TraceHistory logHistory = new TraceHistory(TraceHistory.HistoryType.Log, 'Test', 'message');
    TraceHistory skipHistory = new TraceHistory(TraceHistory.HistoryType.Skip, 'Test', null);
    TraceHistory abortHistory = new TraceHistory(TraceHistory.HistoryType.Abort, 'Test', null);
    TraceHistory finishHistory = new TraceHistory(TraceHistory.HistoryType.Finish, 'Test', null);

    // Act / Assert
    Assert.isTrue(startHistory.isStart());
    Assert.isFalse(startHistory.isLog());
    Assert.isFalse(startHistory.isSkip());
    Assert.isFalse(startHistory.isAbort());
    Assert.isFalse(startHistory.isFinish());

    Assert.isTrue(logHistory.isLog());
    Assert.isFalse(logHistory.isStart());

    Assert.isTrue(skipHistory.isSkip());
    Assert.isFalse(skipHistory.isStart());

    Assert.isTrue(abortHistory.isAbort());
    Assert.isFalse(abortHistory.isStart());

    Assert.isTrue(finishHistory.isFinish());
    Assert.isFalse(finishHistory.isStart());
  }

  @isTest
  static void testContainsText_WhenTextExists_ThenReturnTrue() {
    // Arrange
    TraceHistory history = new TraceHistory(TraceHistory.HistoryType.Log, 'TestContext', 'This is a test message');

    // Act / Assert
    Assert.isTrue(history.containsText('test'));
    Assert.isTrue(history.containsText('message'));
    Assert.isFalse(history.containsText('nonexistent'));
  }

  @isTest
  static void testContainsText_WhenNullMessage_ThenReturnFalse() {
    // Arrange
    TraceHistory history = new TraceHistory(TraceHistory.HistoryType.Start, 'TestContext', null);

    // Act / Assert
    Assert.isFalse(history.containsText('anything'));
  }

  @isTest
  static void testAllHistoryTypes_WhenCreated_ThenTypeIsCorrect() {
    // Arrange / Act
    TraceHistory startHistory = new TraceHistory(TraceHistory.HistoryType.Start, 'Test', null);
    TraceHistory logHistory = new TraceHistory(TraceHistory.HistoryType.Log, 'Test', 'msg');
    TraceHistory skipHistory = new TraceHistory(TraceHistory.HistoryType.Skip, 'Test', 'reason');
    TraceHistory abortHistory = new TraceHistory(TraceHistory.HistoryType.Abort, 'Test', 'reason');
    TraceHistory finishHistory = new TraceHistory(TraceHistory.HistoryType.Finish, 'Test', 'result');

    // Assert
    Assert.areEqual(TraceHistory.HistoryType.Start, startHistory.getType());
    Assert.areEqual(TraceHistory.HistoryType.Log, logHistory.getType());
    Assert.areEqual(TraceHistory.HistoryType.Skip, skipHistory.getType());
    Assert.areEqual(TraceHistory.HistoryType.Abort, abortHistory.getType());
    Assert.areEqual(TraceHistory.HistoryType.Finish, finishHistory.getType());
  }
}

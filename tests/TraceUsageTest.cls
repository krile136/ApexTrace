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
 * @description Test class for TraceUsage
 * Tests snapshot capturing, consumption calculation, assertion helpers, and formatting
 */
@isTest
public with sharing class TraceUsageTest {
  @isTest
  static void testSince_WhenSoqlExecuted_ThenReflectsQueriesAndRows() {
    // Arrange
    TraceUsage startPoint = TraceUsage.capture();

    // Act
    List<User> users = [SELECT Id FROM User LIMIT 1];
    TraceUsage usage = TraceUsage.capture().since(startPoint);

    // Assert
    Assert.areEqual(1, usage.getSoqlQueries());
    Assert.areEqual(users.size(), usage.getSoqlRows());
    Assert.areEqual(0, usage.getDmlStatements());
    Assert.areEqual(0, usage.getDmlRows());
    Assert.areEqual(0, usage.getCallouts());
  }

  @isTest
  static void testSince_WhenDmlExecuted_ThenReflectsStatementsAndRows() {
    // Arrange
    TraceUsage startPoint = TraceUsage.capture();

    // Act
    // Document supports no triggers or validation rules, so the DML can never be
    // broken by consumer-org customization (framework tests run in consumer orgs).
    insert new List<Document>{
      new Document(Name = 'Usage Test 1', FolderId = UserInfo.getUserId()),
      new Document(Name = 'Usage Test 2', FolderId = UserInfo.getUserId())
    };
    TraceUsage usage = TraceUsage.capture().since(startPoint);

    // Assert
    Assert.areEqual(1, usage.getDmlStatements());
    Assert.areEqual(2, usage.getDmlRows());
    Assert.areEqual(0, usage.getSoqlQueries());
  }

  @isTest
  static void testSince_WhenNothingExecuted_ThenAllZero() {
    // Arrange
    TraceUsage startPoint = TraceUsage.capture();

    // Act
    TraceUsage usage = TraceUsage.capture().since(startPoint);

    // Assert
    Assert.areEqual(0, usage.getSoqlQueries());
    Assert.areEqual(0, usage.getSoqlRows());
    Assert.areEqual(0, usage.getDmlStatements());
    Assert.areEqual(0, usage.getDmlRows());
    Assert.areEqual(0, usage.getCallouts());
  }

  @isTest
  static void testAssertAtMost_WhenWithinMaximum_ThenReturnsSelfForChaining() {
    // Arrange
    TraceUsage startPoint = TraceUsage.capture();
    List<User> users = [SELECT Id FROM User LIMIT 1];
    TraceUsage usage = TraceUsage.capture().since(startPoint);

    // Act / Assert - no exception, and every helper returns the same instance
    TraceUsage returned = usage
      .assertSoqlQueriesAtMost(1)
      .assertSoqlRowsAtMost(1)
      .assertDmlStatementsAtMost(0)
      .assertDmlRowsAtMost(0)
      .assertCalloutsAtMost(0);
    Assert.areEqual(usage, returned);
  }

  @isTest
  static void testAssertAtMost_WhenExceeded_ThenThrowsTraceExceptionWithBreakdown() {
    // Arrange
    TraceUsage startPoint = TraceUsage.capture();
    List<User> users = [SELECT Id FROM User LIMIT 1];
    TraceUsage usage = TraceUsage.capture().since(startPoint);

    // Act / Assert
    try {
      usage.assertSoqlQueriesAtMost(0);
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      Assert.isTrue(e.getMessage().contains('SOQL queries is 1'));
      Assert.isTrue(e.getMessage().contains('allowed maximum of 0'));
      Assert.isTrue(e.getMessage().contains('Actual usage: SOQL: 1'));
    }
  }

  @isTest
  static void testFormat_WhenCalled_ThenContainsAllMetrics() {
    // Arrange
    TraceUsage startPoint = TraceUsage.capture();
    List<User> users = [SELECT Id FROM User LIMIT 1];
    insert new Document(Name = 'Usage Format Test', FolderId = UserInfo.getUserId());
    TraceUsage usage = TraceUsage.capture().since(startPoint);

    // Act
    String formatted = usage.format();

    // Assert
    Assert.areEqual('SOQL: 1 (rows: ' + users.size() + '), DML: 1 (rows: 1), Callouts: 0', formatted);
  }
}

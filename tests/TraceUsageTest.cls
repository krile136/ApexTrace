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
 * @description Test class for TraceUsage.
 *
 * Arithmetic, formatting, and assertion helpers are verified with a stub
 * ILimitsReader (synthetic counter values) — fully deterministic and free of
 * SOQL/DML, so consumer-org customization can never break these tests. A single
 * loose test verifies that the production LimitsReader reads real counters.
 */
@isTest
public with sharing class TraceUsageTest {
  /**
   * @description Stub reader whose counter values the test mutates between capture() calls.
   */
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
  static void testSince_WhenCountersAdvance_ThenDiffIsExact() {
    // Arrange
    StubLimitsReader stub = new StubLimitsReader();
    stub.queries = 2;
    stub.queryRows = 10;
    stub.dmlStatements = 1;
    stub.dmlRows = 2;
    stub.callouts = 0;
    TraceUsage.limitsReader = stub;
    TraceUsage startPoint = TraceUsage.capture();

    // Act - advance the counters as if the section consumed governor resources
    stub.queries = 5;
    stub.queryRows = 110;
    stub.dmlStatements = 3;
    stub.dmlRows = 32;
    stub.callouts = 1;
    TraceUsage usage = TraceUsage.capture().since(startPoint);

    // Assert
    Assert.areEqual(3, usage.getSoqlQueries());
    Assert.areEqual(100, usage.getSoqlRows());
    Assert.areEqual(2, usage.getDmlStatements());
    Assert.areEqual(30, usage.getDmlRows());
    Assert.areEqual(1, usage.getCallouts());
  }

  @isTest
  static void testSince_WhenNothingConsumed_ThenAllZero() {
    // Arrange
    StubLimitsReader stub = new StubLimitsReader();
    stub.queries = 7;
    TraceUsage.limitsReader = stub;
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
    StubLimitsReader stub = new StubLimitsReader();
    TraceUsage.limitsReader = stub;
    TraceUsage startPoint = TraceUsage.capture();
    stub.queries = 1;
    stub.queryRows = 1;
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
    StubLimitsReader stub = new StubLimitsReader();
    TraceUsage.limitsReader = stub;
    TraceUsage startPoint = TraceUsage.capture();
    stub.queries = 1;
    TraceUsage usage = TraceUsage.capture().since(startPoint);

    // Act / Assert
    try {
      usage.assertSoqlQueriesAtMost(0);
      Assert.fail('Exception was not thrown.');
    } catch (TraceException e) {
      Assert.isTrue(e.getMessage().contains('SOQL queries is 1'), e.getMessage());
      Assert.isTrue(e.getMessage().contains('allowed maximum of 0'), e.getMessage());
      Assert.isTrue(e.getMessage().contains('Actual usage: SOQL: 1'), e.getMessage());
    }
  }

  @isTest
  static void testFormat_WhenCalled_ThenContainsAllMetrics() {
    // Arrange
    StubLimitsReader stub = new StubLimitsReader();
    TraceUsage.limitsReader = stub;
    TraceUsage startPoint = TraceUsage.capture();
    stub.queries = 1;
    stub.queryRows = 5;
    stub.dmlStatements = 1;
    stub.dmlRows = 1;
    TraceUsage usage = TraceUsage.capture().since(startPoint);

    // Act
    String formatted = usage.format();

    // Assert - synthetic counters make the exact format assertable
    Assert.areEqual('SOQL: 1 (rows: 5), DML: 1 (rows: 1), Callouts: 0', formatted);
  }

  @isTest
  static void testCapture_WhenProductionReader_ThenReadsRealCounters() {
    // Arrange - production LimitsReader (no stub injected)
    TraceUsage startPoint = TraceUsage.capture();

    // Act - a single query against User (safe in any org: no consumer customization
    // can intercept a SOQL read issued by this test)
    List<User> users = [SELECT Id FROM User LIMIT 1];
    TraceUsage usage = TraceUsage.capture().since(startPoint);

    // Assert - loose lower bounds: real counters moved
    Assert.isTrue(usage.getSoqlQueries() >= 1, 'Real SOQL counter should advance: ' + usage.format());
    Assert.isTrue(usage.getSoqlRows() >= users.size(), 'Real row counter should advance: ' + usage.format());
    Assert.areEqual(0, usage.getCallouts());
  }
}

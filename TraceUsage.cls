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
 * @description Represents governor limit consumption between two points in a transaction.
 *
 * TraceFlow captures a snapshot when a context starts and attaches the
 * consumption (calculated with since()) to the history entry that closes
 * the context (Skip / Abort / Finish). This makes the governor cost of each
 * traced section visible in debug logs and assertable in tests.
 *
 * Only deterministic metrics are tracked (SOQL queries / SOQL rows /
 * DML statements / DML rows / callouts) so that assertions are stable.
 * Time- and memory-based limits (CPU, heap) fluctuate between runs and are
 * intentionally excluded.
 *
 * Note: a context's usage includes everything consumed between its start
 * and its close, so a parent context's usage includes its nested children.
 *
 * Usage example (in a test):
 * ```
 * new SomeUsecase(ids).invoke();
 * TraceFlow.lastUsage()
 *   .assertSoqlQueriesAtMost(3)
 *   .assertDmlStatementsAtMost(1);
 * ```
 */
public with sharing class TraceUsage {
  private final Integer soqlQueries;
  private final Integer soqlRows;
  private final Integer dmlStatements;
  private final Integer dmlRows;
  private final Integer callouts;

  /**
   * @description Private constructor holding metric values
   * @param soqlQueries The number of SOQL queries
   * @param soqlRows The number of rows returned by SOQL queries
   * @param dmlStatements The number of DML statements
   * @param dmlRows The number of rows processed by DML statements
   * @param callouts The number of callouts
   */
  private TraceUsage(Integer soqlQueries, Integer soqlRows, Integer dmlStatements, Integer dmlRows, Integer callouts) {
    this.soqlQueries = soqlQueries;
    this.soqlRows = soqlRows;
    this.dmlStatements = dmlStatements;
    this.dmlRows = dmlRows;
    this.callouts = callouts;
  }

  /**
   * @description The governor counter source. Production reads System.Limits;
   * tests inject a stub for deterministic, org-independent verification.
   */
  @TestVisible
  private static ILimitsReader limitsReader = new LimitsReader();

  /**
   * @description Captures the governor limit consumption of the transaction so far
   * @return A TraceUsage snapshot of the current consumption
   */
  public static TraceUsage capture() {
    return new TraceUsage(
      limitsReader.getQueries(),
      limitsReader.getQueryRows(),
      limitsReader.getDmlStatements(),
      limitsReader.getDmlRows(),
      limitsReader.getCallouts()
    );
  }

  /**
   * @description Calculates the consumption between an earlier snapshot and this one
   * @param startPoint The snapshot taken at the start of the section
   * @return A TraceUsage representing what the section consumed
   */
  public TraceUsage since(TraceUsage startPoint) {
    return new TraceUsage(
      this.soqlQueries - startPoint.soqlQueries,
      this.soqlRows - startPoint.soqlRows,
      this.dmlStatements - startPoint.dmlStatements,
      this.dmlRows - startPoint.dmlRows,
      this.callouts - startPoint.callouts
    );
  }

  /**
   * @description Gets the number of SOQL queries
   * @return The SOQL query count
   */
  public Integer getSoqlQueries() {
    return this.soqlQueries;
  }

  /**
   * @description Gets the number of rows returned by SOQL queries
   * @return The SOQL row count
   */
  public Integer getSoqlRows() {
    return this.soqlRows;
  }

  /**
   * @description Gets the number of DML statements
   * @return The DML statement count
   */
  public Integer getDmlStatements() {
    return this.dmlStatements;
  }

  /**
   * @description Gets the number of rows processed by DML statements
   * @return The DML row count
   */
  public Integer getDmlRows() {
    return this.dmlRows;
  }

  /**
   * @description Gets the number of callouts
   * @return The callout count
   */
  public Integer getCallouts() {
    return this.callouts;
  }

  /**
   * @description Asserts that the number of SOQL queries is at most the given maximum
   * @param max The allowed maximum
   * @return This TraceUsage instance (for chaining)
   * @throws TraceException If the actual count exceeds max
   */
  public TraceUsage assertSoqlQueriesAtMost(Integer max) {
    return assertAtMost('SOQL queries', this.soqlQueries, max);
  }

  /**
   * @description Asserts that the number of SOQL rows is at most the given maximum
   * @param max The allowed maximum
   * @return This TraceUsage instance (for chaining)
   * @throws TraceException If the actual count exceeds max
   */
  public TraceUsage assertSoqlRowsAtMost(Integer max) {
    return assertAtMost('SOQL rows', this.soqlRows, max);
  }

  /**
   * @description Asserts that the number of DML statements is at most the given maximum
   * @param max The allowed maximum
   * @return This TraceUsage instance (for chaining)
   * @throws TraceException If the actual count exceeds max
   */
  public TraceUsage assertDmlStatementsAtMost(Integer max) {
    return assertAtMost('DML statements', this.dmlStatements, max);
  }

  /**
   * @description Asserts that the number of DML rows is at most the given maximum
   * @param max The allowed maximum
   * @return This TraceUsage instance (for chaining)
   * @throws TraceException If the actual count exceeds max
   */
  public TraceUsage assertDmlRowsAtMost(Integer max) {
    return assertAtMost('DML rows', this.dmlRows, max);
  }

  /**
   * @description Asserts that the number of callouts is at most the given maximum
   * @param max The allowed maximum
   * @return This TraceUsage instance (for chaining)
   * @throws TraceException If the actual count exceeds max
   */
  public TraceUsage assertCalloutsAtMost(Integer max) {
    return assertAtMost('Callouts', this.callouts, max);
  }

  /**
   * @description Throws a TraceException with the full usage breakdown when actual exceeds max.
   * A TraceException (instead of Assert.fail) is used so that the failure is catchable
   * and therefore testable, while still failing the calling test.
   * @param metric The human-readable metric name
   * @param actual The actual consumed value
   * @param max The allowed maximum
   * @return This TraceUsage instance (for chaining)
   * @throws TraceException If actual exceeds max
   */
  private TraceUsage assertAtMost(String metric, Integer actual, Integer max) {
    if (actual > max) {
      throw new TraceException(
        'Usage assertion failed: ' + metric + ' is ' + actual + ', exceeding the allowed maximum of ' + max + '.\nActual usage: ' + format()
      );
    }
    return this;
  }

  /**
   * @description Formats the usage as a single-line summary
   * @return A summary like 'SOQL: 3 (rows: 120), DML: 1 (rows: 30), Callouts: 0'
   */
  public String format() {
    return 'SOQL: ' + this.soqlQueries + ' (rows: ' + this.soqlRows + '), DML: ' + this.dmlStatements + ' (rows: ' + this.dmlRows + '), Callouts: ' + this.callouts;
  }
}

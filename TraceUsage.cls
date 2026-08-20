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
 * @directory ApexTrace
 */
public with sharing class TraceUsage {
  private final Integer soqlQueries;
  private final Integer soqlRows;
  private final Integer dmlStatements;
  private final Integer dmlRows;
  private final Integer callouts;
  private final Integer invocations;

  /**
   * @description Private constructor holding metric values.
   * Represents a single measured section, so invocations is 1.
   * @param soqlQueries The number of SOQL queries
   * @param soqlRows The number of rows returned by SOQL queries
   * @param dmlStatements The number of DML statements
   * @param dmlRows The number of rows processed by DML statements
   * @param callouts The number of callouts
   */
  private TraceUsage(Integer soqlQueries, Integer soqlRows, Integer dmlStatements, Integer dmlRows, Integer callouts) {
    this(soqlQueries, soqlRows, dmlStatements, dmlRows, callouts, 1);
  }

  /**
   * @description Private constructor for aggregates (usageOf sums)
   * @param soqlQueries The number of SOQL queries
   * @param soqlRows The number of rows returned by SOQL queries
   * @param dmlStatements The number of DML statements
   * @param dmlRows The number of rows processed by DML statements
   * @param callouts The number of callouts
   * @param invocations The number of closed contexts this usage aggregates
   */
  private TraceUsage(
    Integer soqlQueries,
    Integer soqlRows,
    Integer dmlStatements,
    Integer dmlRows,
    Integer callouts,
    Integer invocations
  ) {
    this.soqlQueries = soqlQueries;
    this.soqlRows = soqlRows;
    this.dmlStatements = dmlStatements;
    this.dmlRows = dmlRows;
    this.callouts = callouts;
    this.invocations = invocations;
  }

  /**
   * @description An empty aggregate: zero consumption, zero invocations.
   * The identity element for plus() — TraceFlow.usageOf starts from this, so
   * "the context never ran" comes back as an assertable zero, not null.
   * @return A TraceUsage with all metrics and invocations at 0
   *
   * @internal Aggregation primitive for TraceFlow.usageOf. Not part of the consumer API.
   */
  public static TraceUsage zero() {
    return new TraceUsage(0, 0, 0, 0, 0, 0);
  }

  /**
   * @description Metric-wise sum of two usages; invocations are summed too.
   * Used by TraceFlow.usageOf to aggregate the exclusive consumption of every
   * closed context that carries the same name.
   * @param other The usage to add
   * @return A new TraceUsage holding the sums
   *
   * @internal Aggregation primitive for TraceFlow.usageOf. Not part of the consumer API.
   */
  public TraceUsage plus(TraceUsage other) {
    return new TraceUsage(
      this.soqlQueries + other.soqlQueries,
      this.soqlRows + other.soqlRows,
      this.dmlStatements + other.dmlStatements,
      this.dmlRows + other.dmlRows,
      this.callouts + other.callouts,
      this.invocations + other.invocations
    );
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
   *
   * @internal Called by TraceFlow to snapshot counters. Not part of the consumer API.
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
   *
   * @internal Called by TraceFlow to compute section diffs. Not part of the consumer API.
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
   * @description Gets the number of closed contexts this usage represents.
   * For a single measured section (lastUsage(), usagesOf() entries) this is
   * always 1; for a TraceFlow.usageOf aggregate it is the number of times the
   * named context closed in the transaction (nested re-entries all count).
   * @return The invocation count
   */
  public Integer getInvocations() {
    return this.invocations;
  }

  /**
   * @description Asserts that the number of SOQL queries is at most the given maximum
   * @param max The allowed maximum
   * @return This TraceUsage instance (for chaining)
   * @throws TraceException If the actual count exceeds max
   */
  public TraceUsage assertSoqlQueriesAtMost(Integer max) {
    return assertSoqlQueriesAtMost(max, null);
  }

  /**
   * @description Same as assertSoqlQueriesAtMost(max), carrying a reason that is printed in
   * the failure message (before the numbers). Put the "why" of the threshold
   * here — e.g. the measured baseline and what a jump would mean — so the
   * person who sees the red knows what the guard protects before deciding to
   * raise or delete it.
   * @param max The allowed maximum
   * @param reason Shown as 'Reason: ...' in the failure message (null to omit)
   * @return This TraceUsage instance (for chaining)
   * @throws TraceException If the actual count exceeds max
   */
  public TraceUsage assertSoqlQueriesAtMost(Integer max, String reason) {
    assertMeasured('SOQL queries');
    return assertAtMost('SOQL queries', this.soqlQueries, max, reason);
  }

  /**
   * @description Asserts that the number of SOQL rows is at most the given maximum
   * @param max The allowed maximum
   * @return This TraceUsage instance (for chaining)
   * @throws TraceException If the actual count exceeds max
   */
  public TraceUsage assertSoqlRowsAtMost(Integer max) {
    return assertSoqlRowsAtMost(max, null);
  }

  /**
   * @description Same as assertSoqlRowsAtMost(max), carrying a reason that is printed in
   * the failure message (before the numbers). Put the "why" of the threshold
   * here — e.g. the measured baseline and what a jump would mean — so the
   * person who sees the red knows what the guard protects before deciding to
   * raise or delete it.
   * @param max The allowed maximum
   * @param reason Shown as 'Reason: ...' in the failure message (null to omit)
   * @return This TraceUsage instance (for chaining)
   * @throws TraceException If the actual count exceeds max
   */
  public TraceUsage assertSoqlRowsAtMost(Integer max, String reason) {
    assertMeasured('SOQL rows');
    return assertAtMost('SOQL rows', this.soqlRows, max, reason);
  }

  /**
   * @description Asserts that the number of DML statements is at most the given maximum
   * @param max The allowed maximum
   * @return This TraceUsage instance (for chaining)
   * @throws TraceException If the actual count exceeds max
   */
  public TraceUsage assertDmlStatementsAtMost(Integer max) {
    return assertDmlStatementsAtMost(max, null);
  }

  /**
   * @description Same as assertDmlStatementsAtMost(max), carrying a reason that is printed in
   * the failure message (before the numbers). Put the "why" of the threshold
   * here — e.g. the measured baseline and what a jump would mean — so the
   * person who sees the red knows what the guard protects before deciding to
   * raise or delete it.
   * @param max The allowed maximum
   * @param reason Shown as 'Reason: ...' in the failure message (null to omit)
   * @return This TraceUsage instance (for chaining)
   * @throws TraceException If the actual count exceeds max
   */
  public TraceUsage assertDmlStatementsAtMost(Integer max, String reason) {
    assertMeasured('DML statements');
    return assertAtMost('DML statements', this.dmlStatements, max, reason);
  }

  /**
   * @description Asserts that the number of DML rows is at most the given maximum
   * @param max The allowed maximum
   * @return This TraceUsage instance (for chaining)
   * @throws TraceException If the actual count exceeds max
   */
  public TraceUsage assertDmlRowsAtMost(Integer max) {
    return assertDmlRowsAtMost(max, null);
  }

  /**
   * @description Same as assertDmlRowsAtMost(max), carrying a reason that is printed in
   * the failure message (before the numbers). Put the "why" of the threshold
   * here — e.g. the measured baseline and what a jump would mean — so the
   * person who sees the red knows what the guard protects before deciding to
   * raise or delete it.
   * @param max The allowed maximum
   * @param reason Shown as 'Reason: ...' in the failure message (null to omit)
   * @return This TraceUsage instance (for chaining)
   * @throws TraceException If the actual count exceeds max
   */
  public TraceUsage assertDmlRowsAtMost(Integer max, String reason) {
    assertMeasured('DML rows');
    return assertAtMost('DML rows', this.dmlRows, max, reason);
  }

  /**
   * @description Asserts that the number of callouts is at most the given maximum
   * @param max The allowed maximum
   * @return This TraceUsage instance (for chaining)
   * @throws TraceException If the actual count exceeds max
   */
  public TraceUsage assertCalloutsAtMost(Integer max) {
    return assertCalloutsAtMost(max, null);
  }

  /**
   * @description Same as assertCalloutsAtMost(max), carrying a reason that is printed in
   * the failure message (before the numbers). Put the "why" of the threshold
   * here — e.g. the measured baseline and what a jump would mean — so the
   * person who sees the red knows what the guard protects before deciding to
   * raise or delete it.
   * @param max The allowed maximum
   * @param reason Shown as 'Reason: ...' in the failure message (null to omit)
   * @return This TraceUsage instance (for chaining)
   * @throws TraceException If the actual count exceeds max
   */
  public TraceUsage assertCalloutsAtMost(Integer max, String reason) {
    assertMeasured('Callouts');
    return assertAtMost('Callouts', this.callouts, max, reason);
  }

  /**
   * @description Asserts that the invocation count is at most the given maximum.
   * On a TraceFlow.usageOf aggregate this pins how many times the named context
   * ran in the transaction — the wiring check: an unexpected extra trigger path
   * shows up here as a jump in invocations before any SOQL threshold trips.
   * @param max The allowed maximum
   * @return This TraceUsage instance (for chaining)
   * @throws TraceException If the actual count exceeds max
   */
  public TraceUsage assertInvocationsAtMost(Integer max) {
    return assertInvocationsAtMost(max, null);
  }

  /**
   * @description Same as assertInvocationsAtMost(max), carrying a reason that is printed in
   * the failure message (before the numbers). Put the "why" of the threshold
   * here — e.g. the measured baseline and what a jump would mean — so the
   * person who sees the red knows what the guard protects before deciding to
   * raise or delete it.
   * @param max The allowed maximum
   * @param reason Shown as 'Reason: ...' in the failure message (null to omit)
   * @return This TraceUsage instance (for chaining)
   * @throws TraceException If the actual count exceeds max
   */
  public TraceUsage assertInvocationsAtMost(Integer max, String reason) {
    return assertAtMost('Invocations', this.invocations, max, reason);
  }

  /**
   * @description Rejects consumption assertions on a usage that measured nothing.
   * Writing assertSoqlQueriesAtMost(n) declares "this context ran, bounded by n" —
   * when the named context never closed in the transaction (invocations = 0, the
   * usageOf no-match result), that claim is unfounded and the assert would pass
   * vacuously: a typo'd context name, the wrong test layer, or missing wiring
   * all stay green. Invocation asserts are exempt on purpose —
   * assertInvocationsAtMost(0) is the legitimate way to claim "does not run".
   * @param metric The metric about to be asserted
   * @throws TraceException When invocations is 0
   */
  private void assertMeasured(String metric) {
    if (this.invocations == 0) {
      throw new TraceException(
        'Usage assertion on ' + metric + ' is unfounded: no context with this name closed in the transaction (invocations = 0).' +
          '\nCheck the context name for typos, the test layer, and the wiring.' +
          '\nTo assert that the context does not run, use assertInvocationsAtMost(0).'
      );
    }
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
  private TraceUsage assertAtMost(String metric, Integer actual, Integer max, String reason) {
    if (actual > max) {
      // the Reason line comes BEFORE the numbers: the person reading this failure
      // is about to raise the limit or delete the assert — what the guard protects
      // must reach them before the counts do
      String reasonLine = String.isBlank(reason) ? '' : '\nReason: ' + reason;
      throw new TraceException(
        'Usage assertion failed: ' + metric + ' is ' + actual + ', exceeding the allowed maximum of ' + max + '.' + reasonLine + '\nActual usage: ' + format()
      );
    }
    return this;
  }

  /**
   * @description Formats the usage as a single-line summary.
   * Aggregates (invocations != 1) prefix the invocation count; single-section
   * usages keep the historical format so existing log output is unchanged.
   * @return A summary like 'SOQL: 3 (rows: 120), DML: 1 (rows: 30), Callouts: 0'
   */
  public String format() {
    String prefix = this.invocations == 1 ? '' : 'Invocations: ' + this.invocations + ', ';
    return prefix + 'SOQL: ' + this.soqlQueries + ' (rows: ' + this.soqlRows + '), DML: ' + this.dmlStatements + ' (rows: ' + this.dmlRows + '), Callouts: ' + this.callouts;
  }
}

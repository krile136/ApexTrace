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
 * @description TraceFlow is a static class that manages the nested structure of Trace contexts.
 *
 * This class has a Stack (LIFO) structure and is designed to be operated by
 * Trace.start() / Trace.finish() methods.
 *
 * Design features:
 * - Guarantees the nesting order of Traces
 * - Always treats the currently active context as the top of the Stack
 * - Not intended to be directly operated from classes other than Trace
 *
 * Notes:
 * - This class holds state statically, so it is only valid within a single transaction
 * - Explicit reset is not necessary (it is destroyed at the end of the transaction)
 */
public with sharing class TraceFlow {
  private static List<Trace> traces = new List<Trace>();
  private static List<TraceHistory> histories = new List<TraceHistory>();
  private static List<TraceUsage> startSnapshots = new List<TraceUsage>();

  private static TraceMode mode = Test.isRunningTest() ? TraceMode.Strict : TraceMode.Relaxed;

  /**
   * External sink discovery (issue: standalone-deployable sink packages).
   *
   * The sink is spoken to through System.Callable only — no ApexTrace type
   * crosses the boundary — so a sink package (e.g. ApexLogbook) compiles and
   * deploys without ApexTrace, and vice versa. A class named SINK_CLASS_NAME
   * that implements Callable is discovered once per transaction; when absent,
   * every notification is a no-op.
   *
   * Wire contract (all values are platform types):
   *   action 'trace:onEntry' — one history entry was recorded. args:
   *     'type'        String  Start | Log | Skip | Abort | Finish
   *     'contextName' String
   *     'message'     String  (nullable)
   *     'timestampMs' Long    epoch milliseconds
   *     'depth'       Integer stack depth at recording time (1 = top level)
   *     'usage'       Map<String, Integer> with keys soql / soqlRows / dml /
   *                   dmlRows / callouts, or null for entries that do not
   *                   close a context (Start / Log)
   *   action 'trace:onStackEmpty' — a top-level context closed (the natural
   *     checkpoint to flush). args: null
   *
   * Unknown actions must be ignored by sinks; new actions may be added in
   * later versions without breaking older sinks.
   */
  private static final String SINK_CLASS_NAME = 'Logbook';
  private static final String ACTION_ON_ENTRY = 'trace:onEntry';
  private static final String ACTION_ON_STACK_EMPTY = 'trace:onStackEmpty';

  private static Boolean sinkResolved = false;
  private static Callable sink;

  /**
   * @description Resolves the sink by convention name, once per transaction.
   * Absent class / not Callable / test run (unless overridden) → null.
   * @return The sink, or null when none is active
   */
  private static Callable resolveSink() {
    if (!sinkResolved) {
      sinkResolved = true;
      if (!Test.isRunningTest()) {
        Type sinkType = Type.forName(SINK_CLASS_NAME);
        Object candidate = (sinkType == null) ? null : sinkType.newInstance();
        sink = (candidate instanceof Callable) ? (Callable) candidate : null;
      }
    }
    return sink;
  }

  /**
   * @description Replaces the sink (for testing purposes)
   * @param testSink The sink to inject
   */
  @TestVisible
  private static void overrideSink(Callable testSink) {
    sink = testSink;
    sinkResolved = true;
  }

  /**
   * @description Notifies the sink of a recorded history entry, decomposed
   * into platform types per the wire contract. No-op when no sink is active.
   * @param entry The history entry just recorded
   */
  private static void notifyEntry(TraceHistory entry) {
    Callable target = resolveSink();
    if (target == null) {
      return;
    }
    target.call(
      ACTION_ON_ENTRY,
      new Map<String, Object>{
        'type' => entry.getType().name(),
        'contextName' => entry.getContextName(),
        'message' => entry.getMessage(),
        'timestampMs' => entry.getTimestamp(),
        'depth' => traces.size(),
        'usage' => usageAsMap(entry.getUsage())
      }
    );
  }

  /**
   * @description Notifies the sink that a top-level context closed.
   * No-op when no sink is active.
   */
  private static void notifyStackEmpty() {
    Callable target = resolveSink();
    if (target != null) {
      target.call(ACTION_ON_STACK_EMPTY, null);
    }
  }

  /**
   * @description Decomposes a TraceUsage into the wire-contract map
   * @param usage The usage to decompose (may be null)
   * @return The map, or null when usage is null
   */
  private static Map<String, Integer> usageAsMap(TraceUsage usage) {
    if (usage == null) {
      return null;
    }
    return new Map<String, Integer>{
      'soql' => usage.getSoqlQueries(),
      'soqlRows' => usage.getSoqlRows(),
      'dml' => usage.getDmlStatements(),
      'dmlRows' => usage.getDmlRows(),
      'callouts' => usage.getCallouts()
    };
  }

  /**
   * @description Enum representing the strictness mode of context validation
   */
  @TestVisible
  private enum TraceMode {
    Strict,
    Relaxed
  }

  /**
   * @description Changes the trace mode (for testing purposes)
   * @param newMode The new trace mode to set
   */
  @TestVisible
  private static void changeModeTo(TraceMode newMode) {
    mode = newMode;
  }

  /**
   * @description Checks if the current mode is Strict
   * @return True if the mode is Strict
   */
  private static Boolean isStrict() {
    return mode == TraceMode.Strict;
  }

  /**
   * @description Ensures that the expected context matches the current context
   * In Strict mode, throws an exception if contexts don't match.
   * In Relaxed mode, automatically aborts mismatched contexts.
   *
   * @param expectedContextName The expected context name
   * @param expectedHistoryType The expected history type
   * @throws TraceException If context validation fails
   *
   * @internal Called by Trace to validate lifecycle order. Not part of the consumer API.
   */
  public static void ensureContext(String expectedContextName, TraceHistory.HistoryType expectedHistoryType) {
    if (isStrict()) {
      // In Strict mode, strictly check context consistency
      if (currentContextName() != expectedContextName) {
        String errorMessage = String.format(
          'The context for {0} operation is not the current context.\n Context for {0} operation: {1}\n Current context: {2}',
          new List<String>{ expectedHistoryType.name(), expectedContextName, currentContextName() }
        );
        throw new TraceException(errorMessage)
          .setExpectedContext(expectedContextName)
          .setCurrentContext(currentContextName())
          .setOperationType(expectedHistoryType.name());
      }
    } else {
      // In Relaxed mode, automatically abort if context is wrong
      // However, if expectedContextName is not found even after traces becomes empty, throw an exception
      while (currentContextName() != expectedContextName) {
        if (traces.isEmpty()) {
          String errorMessage = String.format(
            'No matching Trace context found for {1} operation in current context: {0}.',
            new List<String>{ expectedContextName, expectedHistoryType.name() }
          );
          throw new TraceException(errorMessage).setExpectedContext(expectedContextName).setOperationType(expectedHistoryType.name());
        }
        abort('Automatically aborted due to context mismatch. Expected context: ' + expectedContextName);
      }
    }
  }

  /**
   * @description Adds a Trace context to the Stack
   * @param newTrace The Trace to push (does nothing if null)
   *
   * @internal Called by Trace.start(). Consumers use Trace.of(...).start().
   */
  public static void push(Trace newTrace) {
    if (newTrace == null) {
      return;
    }
    traces.add(newTrace);
    startSnapshots.add(TraceUsage.capture());
    String contextName = currentContextName();
    TraceHistory entry = new TraceHistory(TraceHistory.HistoryType.Start, contextName, null);
    histories.add(entry);
    notifyEntry(entry);
    String logMessage = 'START: ' + contextName + ' is starting';
    System.debug(logMessage);
  }

  /**
   * @description Logs a message in the current context
   * @param message The message to log
   *
   * @internal Called by Trace.log(). Consumers use their Trace instance: t.log(...).
   */
  public static void log(String message) {
    String contextName = currentContextName();
    TraceHistory entry = new TraceHistory(TraceHistory.HistoryType.Log, contextName, message);
    histories.add(entry);
    notifyEntry(entry);
    String logMessage = currentContextName() + ': ' + message;
    System.debug(logMessage);
  }

  /**
   * @description Skips the current context without a reason
   *
   * @internal Called by Trace.skip(). Consumers use their Trace instance: t.skip().
   */
  public static void skip() {
    String contextName = currentContextName();
    TraceUsage usage = currentUsage();
    TraceHistory entry = new TraceHistory(TraceHistory.HistoryType.Skip, contextName, null).setUsage(usage);
    histories.add(entry);
    notifyEntry(entry);
    String logMessage = 'SKIP: ' + contextName + ' is skipped' + usageSuffix(usage);
    System.debug(logMessage);
    pop();
  }

  /**
   * @description Skips the current context with a reason
   * @param reason The reason for skipping
   *
   * @internal Called by Trace.skip(reason). Consumers use their Trace instance: t.skip(reason).
   */
  public static void skip(String reason) {
    String contextName = currentContextName();
    TraceUsage usage = currentUsage();
    TraceHistory entry = new TraceHistory(TraceHistory.HistoryType.Skip, contextName, reason).setUsage(usage);
    histories.add(entry);
    notifyEntry(entry);
    String logMessage = 'SKIP: ' + contextName + ' is skipped for the following reason.\nReason: ' + reason + usageSuffix(usage);
    System.debug(logMessage);
    pop();
  }

  /**
   * @description Finishes the current context without a result
   *
   * @internal Called by Trace.finish(). Consumers use their Trace instance: t.finish().
   */
  public static void finish() {
    String contextName = currentContextName();
    TraceUsage usage = currentUsage();
    TraceHistory entry = new TraceHistory(TraceHistory.HistoryType.Finish, contextName, null).setUsage(usage);
    histories.add(entry);
    notifyEntry(entry);
    String logMessage = 'FINISH: ' + contextName + usageSuffix(usage);
    System.debug(logMessage);
    pop();
  }

  /**
   * @description Finishes the current context with a result message
   * @param result The result message
   *
   * @internal Called by Trace.finish(result). Consumers use their Trace instance: t.finish(result).
   */
  public static void finish(String result) {
    String contextName = currentContextName();
    TraceUsage usage = currentUsage();
    TraceHistory entry = new TraceHistory(TraceHistory.HistoryType.Finish, contextName, result).setUsage(usage);
    histories.add(entry);
    notifyEntry(entry);
    String logMessage = 'FINISH: ' + contextName + '\nResult: ' + result + usageSuffix(usage);
    System.debug(logMessage);
    pop();
  }

  /**
   * @description Aborts the current context without a reason
   *
   * @internal Called by Trace.abort(). Consumers use their Trace instance: t.abort().
   */
  public static void abort() {
    String contextName = currentContextName();
    TraceUsage usage = currentUsage();
    TraceHistory entry = new TraceHistory(TraceHistory.HistoryType.Abort, contextName, null).setUsage(usage);
    histories.add(entry);
    notifyEntry(entry);
    String logMessage = 'ABORT: ' + contextName + ' is aborted.' + usageSuffix(usage);
    System.debug(logMessage);
    pop();
  }

  /**
   * @description Aborts the current context with a reason
   * @param result The reason for aborting
   *
   * @internal Called by Trace.abort(reason). Consumers use their Trace instance: t.abort(reason).
   */
  public static void abort(String result) {
    String contextName = currentContextName();
    TraceUsage usage = currentUsage();
    TraceHistory entry = new TraceHistory(TraceHistory.HistoryType.Abort, contextName, result).setUsage(usage);
    histories.add(entry);
    notifyEntry(entry);
    String logMessage = 'ABORT: ' + contextName + ' is aborted for the following reason.\nReason: ' + result + usageSuffix(usage);
    System.debug(logMessage);
    pop();
  }

  /**
   * @description Returns the currently active Trace context name
   * @return The contextName of the top Trace in the Stack, or null if empty
   *
   * @internal Used by Trace and the context validation. Not part of the consumer API.
   */
  public static String currentContextName() {
    if (traces.isEmpty()) {
      return null;
    }
    return traces[traces.size() - 1].getContextName();
  }

  /**
   * @description Removes the current Trace context from the Stack
   * Intended to be called only from Trace.finish().
   * Does nothing if the Stack is empty.
   *
   * @internal Stack maintenance for Trace. Not part of the consumer API.
   */
  public static void pop() {
    if (traces.isEmpty()) {
      return;
    }
    traces.remove(traces.size() - 1);
    if (!startSnapshots.isEmpty()) {
      startSnapshots.remove(startSnapshots.size() - 1);
    }
    if (traces.isEmpty()) {
      // A top-level context closed: the checkpoint boundary for sinks.
      // Fired after the close entry's usage snapshot was taken, so whatever
      // the sink does here is never attributed to the closed context.
      notifyStackEmpty();
    }
  }

  /**
   * @description Calculates the governor usage consumed since the current context started
   * @return The consumed TraceUsage, or null if no start snapshot exists
   */
  private static TraceUsage currentUsage() {
    if (startSnapshots.isEmpty()) {
      return null;
    }
    return TraceUsage.capture().since(startSnapshots[startSnapshots.size() - 1]);
  }

  /**
   * @description Builds the debug log suffix for the given usage
   * @param usage The usage to format (may be null)
   * @return The formatted suffix, or an empty string if usage is null
   */
  private static String usageSuffix(TraceUsage usage) {
    return usage == null ? '' : '\nUsage: ' + usage.format();
  }

  /**
   * @description Gets the governor usage of the most recently closed context.
   * A context's usage includes everything consumed between its start and its
   * close, so a parent context's usage includes its nested children.
   *
   * In Strict mode (test execution) a TraceException is thrown when the call
   * is ambiguous — two or more contexts closed at the same (shallowest) level,
   * e.g. a trigger handler that ran several usecases. lastUsage() would hand
   * back only the last one, silently measuring the wrong thing; the exception
   * lists the candidates so the fix is a copy-paste into usageOf(contextName).
   * In Relaxed mode (production) the guard is skipped entirely.
   *
   * @return The TraceUsage recorded on the most recent Skip / Abort / Finish entry, or null if no context has been closed
   * @throws TraceException In Strict mode when multiple contexts closed at the same level
   */
  public static TraceUsage lastUsage() {
    if (isStrict()) {
      assertLastUsageNotAmbiguous();
    }
    for (Integer i = histories.size() - 1; i >= 0; i--) {
      if (histories[i].getUsage() != null) {
        return histories[i].getUsage();
      }
    }
    return null;
  }

  /**
   * @description Throws when two or more contexts closed at the shallowest close
   * depth. Nesting alone is not ambiguous (the outermost close is the natural
   * target), and the depth baseline is relative — a test wrapping everything in
   * its own Trace.of(...) keeps the stack above zero, so "how many times the
   * stack emptied" would misjudge; the shallowest observed close depth is the
   * correct baseline.
   * @throws TraceException When the most recent usage is ambiguous
   */
  private static void assertLastUsageNotAmbiguous() {
    Integer depth = 0;
    Integer minDepth = null;
    List<String> candidates = new List<String>();
    for (TraceHistory history : histories) {
      if (history.isStart()) {
        depth++;
        continue;
      }
      if (!history.isFinish() && !history.isSkip() && !history.isAbort()) {
        continue; // Log entries do not affect nesting
      }
      if (depth > 0) {
        depth--;
      }
      if (minDepth == null || depth < minDepth) {
        minDepth = depth;
        candidates = new List<String>{ history.getContextName() };
      } else if (depth == minDepth) {
        candidates.add(history.getContextName());
      }
    }
    if (candidates.size() >= 2) {
      throw new TraceException(
        'lastUsage() is ambiguous — ' +
          candidates.size() +
          ' contexts closed at the same level:\n  ' +
          String.join(candidates, ' / ') +
          '\nUse TraceFlow.usageOf(contextName) to target one.'
      );
    }
  }

  /**
   * @description Aggregates the governor usage of every closed context with the
   * given name in this transaction (issue #6).
   *
   * Consumption is summed as EXCLUSIVE usage — each context's own consumption
   * minus its nested children — so nested re-entries of the same name are not
   * double-counted, and consumption of differently-named children is attributed
   * to them, not to this name. Invocations counts every close, nesting included:
   * "invoked 13 times for 39 queries in total" reads off one object.
   *
   * When no context with the name has closed, an assertable zero (0 invocations,
   * zero consumption) is returned, never null. Contexts that never closed
   * (e.g. an exception unwound past them) recorded no usage and are not counted.
   *
   * ```
   * TraceFlow.usageOf('集金オブジェクトの再生成')
   *   .assertInvocationsAtMost(1)
   *   .assertSoqlQueriesAtMost(10);
   * ```
   *
   * @param contextName The context name to aggregate
   * @return The aggregated TraceUsage (never null)
   */
  public static TraceUsage usageOf(String contextName) {
    TraceUsage total = TraceUsage.zero();
    for (TraceUsage exclusive : usagesOf(contextName)) {
      total = total.plus(exclusive);
    }
    return total;
  }

  /**
   * @description Returns the per-invocation EXCLUSIVE usage of every closed
   * context with the given name, in the order they closed (innermost first for
   * nested re-entries). The aggregate usageOf() is the primary API; this is the
   * escape hatch when the per-call breakdown matters.
   * @param contextName The context name to collect
   * @return One TraceUsage per closed context (empty list when none closed)
   */
  public static List<TraceUsage> usagesOf(String contextName) {
    // standard profiler walk: Start pushes a frame, a close pops it;
    // exclusive = own inclusive diff - sum of the direct children's inclusive diffs
    List<TraceUsage> result = new List<TraceUsage>();
    List<TraceUsage> childrenSums = new List<TraceUsage>();
    for (TraceHistory history : histories) {
      if (history.isStart()) {
        childrenSums.add(TraceUsage.zero());
        continue;
      }
      if (!history.isFinish() && !history.isSkip() && !history.isAbort()) {
        continue; // Log entries do not affect nesting
      }
      if (childrenSums.isEmpty()) {
        continue; // defensive: a close without a matching Start
      }
      TraceUsage childrenSum = childrenSums.remove(childrenSums.size() - 1);
      TraceUsage inclusive = history.getUsage();
      if (inclusive == null) {
        continue; // closed without a start snapshot — nothing measurable
      }
      if (!childrenSums.isEmpty()) {
        childrenSums[childrenSums.size() - 1] = childrenSums[childrenSums.size() - 1].plus(inclusive);
      }
      if (history.getContextName() == contextName) {
        result.add(inclusive.since(childrenSum));
      }
    }
    return result;
  }

  /**
   * @description Discards the trace history accumulated so far, so that
   * assertions observe only what happens after this call. Place it at the
   * Arrange / Act boundary of a test, next to Test.startTest():
   *
   * ```
   * setupData();                 // Arrange — trigger-driven usecases traced here
   * TraceFlow.discardArrange();  // ← the same boundary you already write
   * Test.startTest();
   * ```
   *
   * Without it, usageOf() sums Arrange-time invocations into the Act numbers,
   * and path asserts (isLastSkip() etc.) can read an Arrange context when the
   * Act produced none. Only the history is discarded — the open context stack
   * and its usage snapshots are left intact, so a Trace opened before this
   * call (the test's own wrapper) still closes correctly.
   *
   * In Strict mode (test execution) calling this while a usecase context is
   * still open throws: it would erase the Start entry and silently drop that
   * context from usagesOf(). At the boundary, at most the test's own wrapping
   * Trace is open.
   *
   * @throws TraceException In Strict mode when more than one context is open
   */
  public static void discardArrange() {
    if (isStrict() && traces.size() > 1) {
      throw new TraceException(
        'discardArrange() must be called at the Arrange / Act boundary, while no usecase context is open. Currently open: ' +
          traces.size() +
          ' contexts.'
      );
    }
    histories.clear();
  }

  /**
   * @description Returns the last history entry
   * @return The last TraceHistory, or null if empty
   */
  public static TraceHistory lastHistory() {
    if (histories.isEmpty()) {
      return null;
    }
    return histories[histories.size() - 1];
  }

  /**
   * @description Checks if the last history entry is a Start operation
   * @return True if the last history is Start
   */
  @TestVisible
  private static Boolean isLastStart() {
    if (histories.isEmpty()) {
      return false;
    }
    return histories[histories.size() - 1].isStart();
  }

  /**
   * @description Checks if the last history entry is a Log operation
   * @return True if the last history is Log
   */
  @TestVisible
  private static Boolean isLastLog() {
    if (histories.isEmpty()) {
      return false;
    }
    return histories[histories.size() - 1].isLog();
  }

  /**
   * @description Checks if the last history entry is a Skip operation
   * @return True if the last history is Skip
   */
  public static Boolean isLastSkip() {
    if (histories.isEmpty()) {
      return false;
    }
    return histories[histories.size() - 1].isSkip();
  }

  /**
   * @description Checks if the last history entry is an Abort operation
   * @return True if the last history is Abort
   */
  public static Boolean isLastAbort() {
    if (histories.isEmpty()) {
      return false;
    }
    return histories[histories.size() - 1].isAbort();
  }

  /**
   * @description Checks if the last history entry is a Finish operation
   * @return True if the last history is Finish
   */
  public static Boolean isLastFinish() {
    if (histories.isEmpty()) {
      return false;
    }
    return histories[histories.size() - 1].isFinish();
  }

  /**
   * @description Checks if the last history entry contains the specified text
   * @param text The text to search for
   * @return True if the last history contains the text
   */
  public static Boolean lastHistoryContains(String text) {
    if (histories.isEmpty()) {
      return false;
    }
    TraceHistory lastHistory = histories[histories.size() - 1];
    return lastHistory.containsText(text);
  }

  /**
   * @description Checks if any history entry contains the specified text
   * Unlike lastHistoryContains, this searches the entire history,
   * so assertions do not break when the order of entries changes.
   * @param text The text to search for
   * @return True if any history entry contains the text
   */
  public static Boolean contains(String text) {
    for (TraceHistory history : histories) {
      if (history.containsText(text)) {
        return true;
      }
    }
    return false;
  }

  /**
   * @description Gets all history entries
   * @return A copy of the list of all TraceHistory entries
   */
  public static List<TraceHistory> getAllHistories() {
    return new List<TraceHistory>(histories);
  }

  /**
   * @description Gets the count of history entries
   * @return The number of history entries
   */
  @TestVisible
  private static Integer getHistoryCount() {
    return histories.size();
  }

  /**
   * @description Gets the count of traces in the stack
   * @return The number of traces in the stack
   */
  @TestVisible
  private static Integer getStackDepth() {
    return traces.size();
  }

  /**
   * @description Clears all traces and histories (for testing purposes)
   * This method should only be used in test contexts to reset the state
   */
  @TestVisible
  private static void clear() {
    traces.clear();
    histories.clear();
    startSnapshots.clear();
  }

  /**
   * @description Checks if the trace stack is empty
   * @return True if there are no traces in the stack
   *
   * @internal Called by Trace. Not part of the consumer API.
   */
  public static boolean isEmpty() {
    return traces.isEmpty();
  }
}

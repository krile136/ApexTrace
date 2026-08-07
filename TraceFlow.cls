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
    histories.add(new TraceHistory(TraceHistory.HistoryType.Start, contextName, null));
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
    histories.add(new TraceHistory(TraceHistory.HistoryType.Log, contextName, message));
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
    histories.add(new TraceHistory(TraceHistory.HistoryType.Skip, contextName, null).setUsage(usage));
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
    histories.add(new TraceHistory(TraceHistory.HistoryType.Skip, contextName, reason).setUsage(usage));
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
    histories.add(new TraceHistory(TraceHistory.HistoryType.Finish, contextName, null).setUsage(usage));
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
    histories.add(new TraceHistory(TraceHistory.HistoryType.Finish, contextName, result).setUsage(usage));
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
    histories.add(new TraceHistory(TraceHistory.HistoryType.Abort, contextName, null).setUsage(usage));
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
    histories.add(new TraceHistory(TraceHistory.HistoryType.Abort, contextName, result).setUsage(usage));
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

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
          throw new TraceException(errorMessage)
            .setExpectedContext(expectedContextName)
            .setOperationType(expectedHistoryType.name());
        }
        abort('Automatically aborted due to context mismatch. Expected context: ' + expectedContextName);
      }
    }
  }

  /**
   * @description Adds a Trace context to the Stack
   * @param newTrace The Trace to push (does nothing if null)
   */
  public static void push(Trace newTrace) {
    if (newTrace == null) {
      return;
    }
    traces.add(newTrace);
    String contextName = currentContextName();
    histories.add(new TraceHistory(TraceHistory.HistoryType.Start, contextName, null));
    String logMessage = 'START: ' + contextName + ' is starting';
    System.debug(logMessage);
  }

  /**
   * @description Logs a message in the current context
   * @param message The message to log
   */
  public static void log(String message) {
    String contextName = currentContextName();
    histories.add(new TraceHistory(TraceHistory.HistoryType.Log, contextName, message));
    String logMessage = currentContextName() + ': ' + message;
    System.debug(logMessage);
  }

  /**
   * @description Skips the current context without a reason
   */
  public static void skip() {
    String contextName = currentContextName();
    histories.add(new TraceHistory(TraceHistory.HistoryType.Skip, contextName, null));
    String logMessage = 'SKIP: ' + contextName + ' is skipped';
    System.debug(logMessage);
    pop();
  }

  /**
   * @description Skips the current context with a reason
   * @param reason The reason for skipping
   */
  public static void skip(String reason) {
    String contextName = currentContextName();
    histories.add(new TraceHistory(TraceHistory.HistoryType.Skip, contextName, reason));
    String logMessage = 'SKIP: ' + contextName + ' is skipped for the following reason.\nReason: ' + reason;
    System.debug(logMessage);
    pop();
  }

  /**
   * @description Finishes the current context without a result
   */
  public static void finish() {
    String contextName = currentContextName();
    histories.add(new TraceHistory(TraceHistory.HistoryType.Finish, contextName, null));
    String logMessage = 'FINISH: ' + contextName;
    System.debug(logMessage);
    pop();
  }

  /**
   * @description Finishes the current context with a result message
   * @param result The result message
   */
  public static void finish(String result) {
    String contextName = currentContextName();
    histories.add(new TraceHistory(TraceHistory.HistoryType.Finish, contextName, result));
    String logMessage = 'FINISH: ' + contextName + '\nResult: ' + result;
    System.debug(logMessage);
    pop();
  }

  /**
   * @description Aborts the current context without a reason
   */
  public static void abort() {
    String contextName = currentContextName();
    histories.add(new TraceHistory(TraceHistory.HistoryType.Abort, contextName, null));
    String logMessage = 'ABORT: ' + contextName + ' is aborted.';
    System.debug(logMessage);
    pop();
  }

  /**
   * @description Aborts the current context with a reason
   * @param result The reason for aborting
   */
  public static void abort(String result) {
    String contextName = currentContextName();
    histories.add(new TraceHistory(TraceHistory.HistoryType.Abort, contextName, result));
    String logMessage = 'ABORT: ' + contextName + ' is aborted for the following reason.\nReason: ' + result;
    System.debug(logMessage);
    pop();
  }

  /**
   * @description Returns the currently active Trace context name
   * @return The contextName of the top Trace in the Stack, or null if empty
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
   */
  public static void pop() {
    if (traces.isEmpty()) {
      return;
    }
    traces.remove(traces.size() - 1);
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
  public static Boolean isLastStart() {
    if (histories.isEmpty()) {
      return false;
    }
    return histories[histories.size() - 1].isStart();
  }

  /**
   * @description Checks if the last history entry is a Log operation
   * @return True if the last history is Log
   */
  public static Boolean isLastLog() {
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
   * @description Gets the last history entry (instance method)
   * @return The last TraceHistory, or null if empty
   */
  public TraceHistory getLastHistory() {
    if (histories.isEmpty()) {
      return null;
    }
    return histories[histories.size() - 1];
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
  public static Integer getHistoryCount() {
    return histories.size();
  }

  /**
   * @description Gets the count of traces in the stack
   * @return The number of traces in the stack
   */
  public static Integer getStackDepth() {
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
  }

  /**
   * @description Checks if the trace stack is empty
   * @return True if there are no traces in the stack
   */
  public static boolean isEmpty() {
    return traces.isEmpty();
  }
}

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
 * @description Trace manages the start-to-end of processing as an explicit "context",
 * ensuring the order and nested structure of log output.
 *
 * This class is based on the following design principles:
 *
 * - Allow log output only within the range enclosed by START / END
 * - Strictly manage nested contexts with a Stack structure
 * - Lifecycle calls (log / skip / finish / abort) in the wrong order (forgotten END, log output from
 *   outer context, etc.) throw immediately in tests (Strict mode). In production (Relaxed mode) they never
 *   throw: Traces left open above a Trace are aborted when a later lifecycle call on that Trace comes
 *   (a Trace with no later call stays open until the transaction ends), and a call on a Trace that is
 *   not running is skipped with a warning in the debug log. Trace.of(null) / Trace.of('') throw in both modes
 *
 * Main uses:
 * - Visualization of processing flow for Trigger / Service / UseCase units
 * - Structured log analysis by LogAnalyzer, etc.
 *
 * Usage example:
 * ```
 * Trace trace = Trace.of('QuoteRecalculation');
 * trace.start();
 * trace.log('Starting');
 * ...
 * trace.finish();
 * ```
 *
 * Nesting example:
 * ```
 * Trace outer = Trace.of('Outer');
 * outer.start();
 * Trace inner = Trace.of('Inner');
 * inner.start();
 * inner.log('inner processing');
 * inner.finish();
 * outer.log('outer processing');
 * outer.finish();
 * ```
 *
 * Notes:
 * - log() / finish() must always be called from the "current context"
 * - Lifecycle calls on the wrong Trace throw a TraceException in tests (Strict mode) and are skipped in
 *   production (Relaxed mode). Keep the started instance: a Trace re-created with Trace.of(...) is a
 *   different Trace, even with the same name
 * @directory ApexTrace
 */
public with sharing class Trace {
  private final String contextName;

  /**
   * @description Private constructor to create a Trace instance
   * @param contextName The name identifying the context
   */
  private Trace(String contextName) {
    this.contextName = contextName;
  }

  /**
   * @description Gets the context name of this Trace
   * @return The context name
   */
  public String getContextName() {
    return this.contextName;
  }

  /**
   * @description Creates a new Trace context
   * @param contextName The name identifying the context (cannot be null or empty)
   * @return The created Trace instance
   * @throws TraceException If contextName is null or empty
   */
  public static Trace of(String contextName) {
    if (contextName == null) {
      throw new TraceException('Context name is null.');
    }
    if (contextName == '') {
      throw new TraceException('Context name is empty.');
    }
    Trace newTrace = new Trace(contextName);
    return newTrace;
  }

  /**
   * @description Pushes this Trace to TraceFlow and starts the context
   */
  public void start() {
    TraceFlow.push(this);
  }

  /**
   * @description Outputs a log message associated with the current Trace context
   *
   * In Strict mode (tests), this method can only be executed when the calling Trace instance
   * is the current context of TraceFlow (a Trace re-created with the same name does not match).
   * In Relaxed mode (production), Traces left open above it are aborted first.
   *
   * @param message The log message to output
   * A null or empty message is recorded as "Trace log message is null." / "... is empty."
   *
   * @throws TraceException In Strict mode (tests), if the Trace context is undefined or does not match the current context. Relaxed mode (production) skips the call instead (issue #14)
   */
  public void log(String message) {
    if (!TraceFlow.ensureContext(this, TraceHistory.HistoryType.Log)) {
      return;
    }
    if (message == null) {
      TraceFlow.log('Trace log message is null.');
      return;
    }
    if (message == '') {
      TraceFlow.log('Trace log message is empty.');
      return;
    }
    TraceFlow.log(message);
  }

  /**
   * @description Skips the current Trace context
   * @throws TraceException In Strict mode (tests), if the Trace context is undefined or does not match the current context. Relaxed mode (production) skips the call instead (issue #14)
   */
  public void skip() {
    if (!TraceFlow.ensureContext(this, TraceHistory.HistoryType.Skip)) {
      return;
    }
    TraceFlow.skip();
  }

  /**
   * @description Skips the current Trace context with a reason message
   * @param message The reason for skipping
   * @throws TraceException In Strict mode (tests), if the Trace context is undefined or does not match the current context. Relaxed mode (production) skips the call instead (issue #14)
   */
  public void skip(String message) {
    if (!TraceFlow.ensureContext(this, TraceHistory.HistoryType.Skip)) {
      return;
    }
    TraceFlow.skip(message);
  }

  /**
   * @description Ends the Trace context and pops it from TraceFlow
   *
   * finish() must always be called from the "current context".
   * If you try to finish() an outer Trace while nested, an exception will be thrown.
   *
   * @throws TraceException In Strict mode (tests), if it does not match the current Trace context. Relaxed mode (production) skips the call instead (issue #14)
   */
  public void finish() {
    if (!TraceFlow.ensureContext(this, TraceHistory.HistoryType.Finish)) {
      return;
    }
    TraceFlow.finish();
  }

  /**
   * @description Ends the Trace context with a result message and pops it from TraceFlow
   * @param message The result message
   * @throws TraceException In Strict mode (tests), if it does not match the current Trace context. Relaxed mode (production) skips the call instead (issue #14)
   */
  public void finish(String message) {
    if (!TraceFlow.ensureContext(this, TraceHistory.HistoryType.Finish)) {
      return;
    }
    TraceFlow.finish(message);
  }

  /**
   * @description Aborts the current Trace context
   * @throws TraceException In Strict mode (tests), if the Trace context is undefined or does not match the current context. Relaxed mode (production) skips the call instead (issue #14)
   */
  public void abort() {
    if (!TraceFlow.ensureContext(this, TraceHistory.HistoryType.Abort)) {
      return;
    }
    TraceFlow.abort();
  }

  /**
   * @description Aborts the current Trace context with a reason message
   * @param message The reason for aborting
   * @throws TraceException In Strict mode (tests), if the Trace context is undefined or does not match the current context. Relaxed mode (production) skips the call instead (issue #14)
   */
  public void abort(String message) {
    if (!TraceFlow.ensureContext(this, TraceHistory.HistoryType.Abort)) {
      return;
    }
    TraceFlow.abort(message);
  }
}

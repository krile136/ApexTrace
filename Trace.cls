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
 * - Immediately throw an exception for incorrect order (forgotten END, log output from outer context, etc.)
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
 * - Invalid calls will throw a TraceException
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
   * @throws TraceException If the context cannot be started
   */
  public void start() {
    TraceFlow.push(this);
  }

  /**
   * @description Outputs a log message associated with the current Trace context
   *
   * This method can only be executed when the current context of TraceFlow
   * matches the contextName of the calling Trace.
   *
   * @param message The log message to output (cannot be null or empty)
   * @throws TraceException
   *   - If message is null or empty
   *   - If it does not match the current Trace context
   */
  public void log(String message) {
    if (TraceFlow.isEmpty()) {
      throw new TraceException('Trace context is undefined. Please execute the start method of the Trace instance.');
    }

    if(message == null) {
      TraceFlow.log('Trace log message is null.');
      return;
    }

    if(message == '') {
      TraceFlow.log('Trace log message is empty.');
      return;
    }

    TraceFlow.ensureContext(this.contextName, TraceHistory.HistoryType.Log);
    TraceFlow.log(message);
  }

  /**
   * @description Skips the current Trace context
   * @throws TraceException If the Trace context is undefined or does not match the current context
   */
  public void skip() {
    if (TraceFlow.isEmpty()) {
      throw new TraceException('Trace context is undefined. Please execute the start method of the Trace instance.');
    }

    TraceFlow.ensureContext(this.contextName, TraceHistory.HistoryType.Skip);
    TraceFlow.skip();
  }

  /**
   * @description Skips the current Trace context with a reason message
   * @param message The reason for skipping
   * @throws TraceException If the Trace context is undefined or does not match the current context
   */
  public void skip(String message) {
    if (TraceFlow.isEmpty()) {
      throw new TraceException('Trace context is undefined. Please execute the start method of the Trace instance.');
    }

    TraceFlow.ensureContext(this.contextName, TraceHistory.HistoryType.Skip);
    TraceFlow.skip(message);
  }

  /**
   * @description Ends the Trace context and pops it from TraceFlow
   *
   * finish() must always be called from the "current context".
   * If you try to finish() an outer Trace while nested, an exception will be thrown.
   *
   * @throws TraceException If it does not match the current Trace context
   */
  public void finish() {
    if (TraceFlow.isEmpty()) {
      throw new TraceException('Trace context is undefined. Please execute the start method of the Trace instance.');
    }

    TraceFlow.ensureContext(this.contextName, TraceHistory.HistoryType.Finish);
    TraceFlow.finish();
  }

  /**
   * @description Ends the Trace context with a result message and pops it from TraceFlow
   * @param message The result message
   * @throws TraceException If it does not match the current Trace context
   */
  public void finish(String message) {
    if (TraceFlow.isEmpty()) {
      throw new TraceException('Trace context is undefined. Please execute the start method of the Trace instance.');
    }

    TraceFlow.ensureContext(this.contextName, TraceHistory.HistoryType.Finish);
    TraceFlow.finish(message);
  }

  /**
   * @description Aborts the current Trace context
   * @throws TraceException If the Trace context is undefined or does not match the current context
   */
  public void abort() {
    if (TraceFlow.isEmpty()) {
      throw new TraceException('Trace context is undefined. Please execute the start method of the Trace instance.');
    }

    TraceFlow.ensureContext(this.contextName, TraceHistory.HistoryType.Abort);
    TraceFlow.abort();
  }

  /**
   * @description Aborts the current Trace context with a reason message
   * @param message The reason for aborting
   * @throws TraceException If the Trace context is undefined or does not match the current context
   */
  public void abort(String message) {
    if (TraceFlow.isEmpty()) {
      throw new TraceException('Trace context is undefined. Please execute the start method of the Trace instance.');
    }

    TraceFlow.ensureContext(this.contextName, TraceHistory.HistoryType.Abort);
    TraceFlow.abort(message);
  }
}

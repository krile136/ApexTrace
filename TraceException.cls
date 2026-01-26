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
 * @description Custom exception class for Trace-related errors
 * Thrown when there are issues with Trace context management,
 * invalid operations, or incorrect usage of the Trace API.
 *
 * This exception provides additional context about the error:
 * - The current context name when the error occurred
 * - The expected context name (if applicable)
 * - The operation type that was attempted
 */
public with sharing class TraceException extends Exception {
  private String currentContext;
  private String expectedContext;
  private String operationType;

  /**
   * @description Gets the current context name when the exception was thrown
   * @return The current context name, or null if not applicable
   */
  public String getCurrentContext() {
    return this.currentContext;
  }

  /**
   * @description Gets the expected context name when the exception was thrown
   * @return The expected context name, or null if not applicable
   */
  public String getExpectedContext() {
    return this.expectedContext;
  }

  /**
   * @description Gets the operation type that was attempted when the exception was thrown
   * @return The operation type (e.g., 'Log', 'Finish', 'Skip', 'Abort'), or null if not applicable
   */
  public String getOperationType() {
    return this.operationType;
  }

  /**
   * @description Sets the current context information for this exception
   * @param currentContext The current context name
   * @return This TraceException instance for method chaining
   */
  public TraceException setCurrentContext(String currentContext) {
    this.currentContext = currentContext;
    return this;
  }

  /**
   * @description Sets the expected context information for this exception
   * @param expectedContext The expected context name
   * @return This TraceException instance for method chaining
   */
  public TraceException setExpectedContext(String expectedContext) {
    this.expectedContext = expectedContext;
    return this;
  }

  /**
   * @description Sets the operation type information for this exception
   * @param operationType The operation type that was attempted
   * @return This TraceException instance for method chaining
   */
  public TraceException setOperationType(String operationType) {
    this.operationType = operationType;
    return this;
  }
}

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
 * @description Represents a single history entry in the Trace flow
 * Captures the type of operation (Start, Log, Skip, Abort, Finish),
 * the context name, message, and timestamp.
 */
public with sharing class TraceHistory {
  /**
   * @description Enum representing the type of Trace operation
   */
  public enum HistoryType {
    Start,
    Log,
    Skip,
    Abort,
    Finish
  }

  private HistoryType type;
  private String contextName;
  private String message;
  private Long timestamp;

  /**
   * @description Constructor to create a TraceHistory entry
   * @param type The type of Trace operation
   * @param contextName The context name associated with this history entry
   * @param message Optional message associated with the operation
   */
  public TraceHistory(HistoryType type, String contextName, String message) {
    this.type = type;
    this.contextName = contextName;
    this.message = message;
    this.timestamp = DateTime.now().getTime();
  }

  /**
   * @description Gets the type of this history entry
   * @return The HistoryType of this entry
   */
  public HistoryType getType() {
    return this.type;
  }

  /**
   * @description Gets the context name of this history entry
   * @return The context name
   */
  public String getContextName() {
    return this.contextName;
  }

  /**
   * @description Gets the message of this history entry
   * @return The message, or null if no message was provided
   */
  public String getMessage() {
    return this.message;
  }

  /**
   * @description Gets the timestamp of this history entry
   * @return The timestamp in milliseconds since epoch
   */
  public Long getTimestamp() {
    return this.timestamp;
  }

  /**
   * @description Gets the DateTime representation of this history entry's timestamp
   * @return The DateTime object
   */
  public DateTime getDateTime() {
    return DateTime.newInstance(this.timestamp);
  }

  /**
   * @description Checks if this history entry is a Start operation
   * @return True if this is a Start operation
   */
  public Boolean isStart() {
    return this.type == HistoryType.Start;
  }

  /**
   * @description Checks if this history entry is a Log operation
   * @return True if this is a Log operation
   */
  public Boolean isLog() {
    return this.type == HistoryType.Log;
  }

  /**
   * @description Checks if this history entry is a Skip operation
   * @return True if this is a Skip operation
   */
  public Boolean isSkip() {
    return this.type == HistoryType.Skip;
  }

  /**
   * @description Checks if this history entry is an Abort operation
   * @return True if this is an Abort operation
   */
  public Boolean isAbort() {
    return this.type == HistoryType.Abort;
  }

  /**
   * @description Checks if this history entry is a Finish operation
   * @return True if this is a Finish operation
   */
  public Boolean isFinish() {
    return this.type == HistoryType.Finish;
  }

  /**
   * @description Checks if the message contains the specified text
   * @param text The text to search for in the message
   * @return True if the message contains the text, false otherwise
   */
  public Boolean containsText(String text) {
    return this.message != null && this.message.contains(text);
  }
}

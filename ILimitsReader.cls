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
 * @description Abstraction over the governor limit counters read by TraceUsage.
 *
 * Production uses LimitsReader (thin wrapper over System.Limits). Tests inject a
 * stub with synthetic values, so usage arithmetic, formatting, and assertion
 * helpers are verified deterministically without issuing any SOQL or DML —
 * framework tests stay independent of consumer-org customization.
 */
public interface ILimitsReader {
  Integer getQueries();
  Integer getQueryRows();
  Integer getDmlStatements();
  Integer getDmlRows();
  Integer getCallouts();
}

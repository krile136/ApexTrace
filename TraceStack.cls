/**
 * TraceStack は、Trace コンテキストのネスト構造を管理するstaticクラスです。
 *
 * このクラスは Stack (LIFO) 構造を持ち、
 * Trace.start() / Trace.end() によって操作されることを前提としています。
 *
 * 設計上の特徴:
 * - Trace のネスト順序を保証する
 * - 現在有効なコンテキストを常に Stack の最上位として扱う
 * - Trace クラス以外から直接操作されることを想定していない
 *
 * 注意:
 * - 本クラスは状態を static に保持するため、1トランザクション内でのみ有効です
 * - 明示的な reset は不要（トランザクション終了時に破棄されます）
 */
public with sharing class TraceStack {
  private static List<Trace> traces = new List<Trace>();
  private static List<TraceHistory> histories = new List<TraceHistory>();

  private static TraceMode mode = Test.isRunningTest() ? TraceMode.Strict : TraceMode.Relaxed;

  @TestVisible
  private enum TraceMode {
    Strict,
    Relaxed
  }

  @TestVisible
  private static void changeModeTo(TraceMode newMode) {
    mode = newMode;
  }

  private static Boolean isStrict() {
    return mode == TraceMode.Strict;
  }

  public static void ensureContext(String expectedContextName, TraceHistory.HistoryType expectedHistoryType) {
    if (isStrict()) {
      // Stringモードではコンテキストの整合性を厳密にチェックする
      if (currentContextName() != expectedContextName) {
        String errorMessage = String.format(
          '{0}操作を行うコンテキストが、現在のコンテキストではありません。\n {0} 操作を行うコンテキスト: {1}\n 現在のコンテキスト {2}',
          new List<String>{ expectedHistoryType.name(), expectedContextName, currentContextName() }
        );
        throw new TraceException(errorMessage);
      }
    } else {
      // Relaxedモードではコンテキストがおかしい場合は自動的にabortする
      // ただしtracesがからになってもexpectedContextNameが見つからない場合は例外をスローする
      while (currentContextName() != expectedContextName) {
        if (traces.isEmpty()) {
          String errorMessage = String.format(
            '現在のコンテキスト: {0} の{1} 操作に一致するTraceコンテキストが見つかりません。',
            new List<String>{ expectedContextName, expectedHistoryType.name() }
          );
          throw new TraceException(errorMessage);
        }
        abort('コンテキスト不整合のため自動中断されました。期待されるコンテキスト: ' + expectedContextName);
      }
    }
  }

  /**
   * Trace コンテキストを Stack に追加します。
   *
   * @param newTrace push 対象の Trace（null の場合は何もしません）
   */
  public static void push(Trace newTrace) {
    if (newTrace == null) {
      return;
    }
    traces.add(newTrace);
    String contextName = currentContextName();
    histories.add(new TraceHistory(TraceHistory.HistoryType.Start, contextName, null));
    String logMessage = 'START: ' + contextName + ' を開始します';
    System.debug(logMessage);
  }

  public static void log(String message) {
    String contextName = currentContextName();
    histories.add(new TraceHistory(TraceHistory.HistoryType.Log, contextName, message));
    String logMessage = currentContextName() + ': ' + message;
    System.debug(logMessage);
  }

  public static void skip() {
    String contextName = currentContextName();
    histories.add(new TraceHistory(TraceHistory.HistoryType.Skip, contextName, null));
    String logMessage = 'SKIP: ' + contextName + ' をスキップします';
    System.debug(logMessage);
    pop();
  }

  public static void skip(String reason) {
    String contextName = currentContextName();
    histories.add(new TraceHistory(TraceHistory.HistoryType.Skip, contextName, reason));
    String logMessage = 'SKIP: ' + contextName + ' を次の理由のためスキップします。\n理由: ' + reason;
    System.debug(logMessage);
    pop();
  }

  public static void finish() {
    String contextName = currentContextName();
    histories.add(new TraceHistory(TraceHistory.HistoryType.Finish, contextName, null));
    String logMessage = 'FINISH: ' + contextName;
    System.debug(logMessage);
    pop();
  }

  public static void finish(String result) {
    String contextName = currentContextName();
    histories.add(new TraceHistory(TraceHistory.HistoryType.Finish, contextName, result));
    String logMessage = 'FINISH: ' + contextName + '\n結果: ' + result;
    System.debug(logMessage);
    pop();
  }

  public static void abort() {
    String contextName = currentContextName();
    histories.add(new TraceHistory(TraceHistory.HistoryType.Abort, contextName, null));
    String logMessage = 'ABORT: ' + contextName + 'を中断します。';
    System.debug(logMessage);
    pop();
  }

  public static void abort(String result) {
    String contextName = currentContextName();
    histories.add(new TraceHistory(TraceHistory.HistoryType.Abort, contextName, result));
    String logMessage = 'ABORT: ' + contextName + 'を次の理由のため中断します。\n理由: ' + result;
    System.debug(logMessage);
    pop();
  }

  /**
   * 現在有効な Trace コンテキスト名を返します。
   *
   * @return Stack 最上位の Trace の contextName
   * @throws ListException Stack が空の場合
   */
  public static String currentContextName() {
    if (traces.isEmpty()) {
      return null;
    }
    return traces[traces.size() - 1].getContextName();
  }

  /**
   * 現在の Trace コンテキストを Stack から削除します。
   *
   * Trace.end() からのみ呼び出されることを想定しています。
   * Stack が空の場合は何も行いません。
   */
  public static void pop() {
    if (traces.isEmpty()) {
      return;
    }
    traces.remove(traces.size() - 1);
  }

  public static TraceHistory lastHistory() {
    if (histories.isEmpty()) {
      return null;
    }
    return histories[histories.size() - 1];
  }

  public static Boolean isLastStart() {
    if (histories.isEmpty()) {
      return false;
    }
    return histories[histories.size() - 1].isStart();
  }

  public static Boolean isLastLog() {
    if (histories.isEmpty()) {
      return false;
    }
    return histories[histories.size() - 1].isLog();
  }

  public static Boolean isLastSkip() {
    if (histories.isEmpty()) {
      return false;
    }
    return histories[histories.size() - 1].isSkip();
  }

  public static Boolean isLastAbort() {
    if (histories.isEmpty()) {
      return false;
    }
    return histories[histories.size() - 1].isAbort();
  }

  public static Boolean isLastFinish() {
    if (histories.isEmpty()) {
      return false;
    }
    return histories[histories.size() - 1].isFinish();
  }

  public static Boolean lastHistoryContains(String text) {
    if (histories.isEmpty()) {
      return false;
    }
    TraceHistory lastHistory = histories[histories.size() - 1];
    return lastHistory.containsText(text);
  }

  public TraceHistory getLastHistory() {
    if (histories.isEmpty()) {
      return null;
    }
    return histories[histories.size() - 1];
  }

  public static boolean isEmpty() {
    return traces.isEmpty();
  }
}

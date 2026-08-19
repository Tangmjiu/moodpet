/// AgentLogger — a lightweight in-memory ring-buffer log service for the
/// PocketClaw agent, LLM client and provider layers.
///
/// Designed for diagnosability: when an LLM call fails or returns unparseable
/// output, the user can open the log viewer (settings → 日志查看器) and see
/// exactly what happened — HTTP status, response body, parse errors — without
/// needing a debugger.
///
/// Single-process singleton. Not persisted across app restarts by design: logs
/// are diagnostic, not audit-grade. A future revision may add file-based
/// rotation; for now the ring buffer caps memory at ~500 entries.
library;

import 'dart:async';

/// Log severity. Ordered: error > warn > info.
enum LogLevel {
  /// Call failed or output was unparseable — the user-visible behaviour was
  /// affected (e.g. agent returned an error instead of an emotion response).
  error,

  /// Recoverable degradation — the call fell back but the user was not
  /// blocked (e.g. LLM returned non-JSON, keyword fallback used).
  warn,

  /// Normal lifecycle — call succeeded, configuration resolved, etc.
  info,
}

/// A single log entry. Immutable.
class LogEntry {
  /// When the event occurred (local clock).
  final DateTime timestamp;

  /// Severity.
  final LogLevel level;

  /// Source layer: `'agent'`, `'llm'`, `'provider'`, etc.
  final String category;

  /// Human-readable summary (one line, ≤ 200 chars preferred).
  final String message;

  /// Optional raw payload — the LLM response body, the request URL, the parse
  /// failure excerpt. Shown only when the entry is expanded in the viewer.
  final String? rawPayload;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.rawPayload,
  });

  /// One-line summary for the list view: `[HH:mm:ss.SSS] LEVEL category: message`.
  String get summary {
    final t = _formatTime(timestamp);
    final lvl = level.name.toUpperCase().padLeft(5);
    return '[$t] $lvl $category: $message';
  }

  /// Plain-text block for the export / expanded view.
  String toExportBlock() {
    final buf = StringBuffer()
      ..writeln('[$timestamp] ${level.name.toUpperCase()} [$category]')
      ..writeln('  message: $message');
    if (rawPayload != null && rawPayload!.isNotEmpty) {
      buf
        ..writeln('  payload:')
        ..write(_indent(rawPayload!, 4));
    }
    return buf.toString();
  }

  static String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}';
  }

  static String _indent(String s, int n) {
    final pad = ' ' * n;
    return s.split('\n').map((l) => '$pad$l').join('\n');
  }
}

/// The singleton logger. Hold no reference to UI; the viewer subscribes via
/// [changes] and pulls the current buffer via [entries].
class AgentLogger {
  AgentLogger._() {
    // Emit the current buffer as the first event so a late subscriber sees
    // existing entries without a separate read.
    _controller.add(_buffer);
  }

  /// The single instance.
  static final AgentLogger instance = AgentLogger._();

  /// Maximum entries kept in memory. Older entries are dropped FIFO.
  static const int kMaxEntries = 500;

  final List<LogEntry> _buffer = <LogEntry>[];
  final StreamController<List<LogEntry>> _controller =
      StreamController<List<LogEntry>>.broadcast();

  /// Unmodifiable view of the buffer, **newest first** (the most recent log
  /// is `entries.first`). The internal buffer is stored oldest-first for
  /// efficient append; this accessor reverses on each read. With a 500-entry
  /// cap the cost is negligible.
  List<LogEntry> get entries =>
      List<LogEntry>.unmodifiable(_buffer.reversed);

  /// Stream that emits the current full buffer on every add/clear. Use this to
  /// rebuild the log viewer UI.
  Stream<List<LogEntry>> get changes => _controller.stream;

  /// Append a log entry. Trims the buffer to [kMaxEntries] (FIFO eviction).
  void log(
    LogLevel level,
    String category,
    String message, {
    String? rawPayload,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: message,
      rawPayload: rawPayload,
    );
    _buffer.add(entry);
    if (_buffer.length > kMaxEntries) {
      _buffer.removeRange(0, _buffer.length - kMaxEntries);
    }
    _controller.add(List<LogEntry>.unmodifiable(_buffer.reversed));
  }

  /// Convenience wrappers for the three levels.
  void error(String category, String message, {String? rawPayload}) =>
      log(LogLevel.error, category, message, rawPayload: rawPayload);
  void warn(String category, String message, {String? rawPayload}) =>
      log(LogLevel.warn, category, message, rawPayload: rawPayload);
  void info(String category, String message, {String? rawPayload}) =>
      log(LogLevel.info, category, message, rawPayload: rawPayload);

  /// Drop every entry and notify subscribers.
  void clear() {
    _buffer.clear();
    _controller.add(const <LogEntry>[]);
  }

  /// Format the whole buffer as plain text for export. Oldest-first so the
  /// exported file reads chronologically.
  String exportAsText() {
    final buf = StringBuffer()
      ..writeln('MoodPet 日志导出')
      ..writeln('导出时间: ${DateTime.now()}')
      ..writeln('条目数: ${_buffer.length}')
      ..writeln('———————————————');
    for (final e in _buffer) {
      buf.writeln(e.toExportBlock());
    }
    return buf.toString();
  }

  /// Tear down the stream controller. Only call from app dispose / tests.
  void dispose() {
    _controller.close();
  }
}

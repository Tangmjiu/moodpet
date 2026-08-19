/// Conversation store — persistent dialogue history across app restarts.
///
/// Stores user ↔ partner exchanges as a JSON file in the app support
/// directory. On launch the agent loads recent history and feeds it to the
/// LLM as context, so the partner "remembers" what was said before. This is
/// the simplest viable memory: a flat append-only log with a size cap, no
/// summarisation or semantic recall.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// One turn in the conversation.
class ConversationTurn {
  final DateTime timestamp;
  final String userInput;
  final String partnerReply;

  const ConversationTurn({
    required this.timestamp,
    required this.userInput,
    required this.partnerReply,
  });

  Map<String, Object?> toJson() => <String, Object?>{
        'timestamp': timestamp.toIso8601String(),
        'user': userInput,
        'partner': partnerReply,
      };

  factory ConversationTurn.fromJson(Map<String, Object?> json) {
    final ts = json['timestamp'];
    final user = json['user'];
    final partner = json['partner'];
    if (user is! String || partner is! String) {
      throw const FormatException(
          'ConversationTurn requires string user/partner');
    }
    return ConversationTurn(
      timestamp: ts is String ? DateTime.tryParse(ts) ?? DateTime.now() : DateTime.now(),
      userInput: user,
      partnerReply: partner,
    );
  }
}

/// Persistent conversation log backed by a JSON file on disk.
class ConversationStore {
  ConversationStore._(this._file, this._turns);

  static const int kMaxTurns = 200;

  final File _file;
  final List<ConversationTurn> _turns;
  final StreamController<List<ConversationTurn>> _controller =
      StreamController<List<ConversationTurn>>.broadcast();

  /// All turns, oldest-first.
  List<ConversationTurn> get turns =>
      List<ConversationTurn>.unmodifiable(_turns);

  /// Stream that emits the current turns on every append/clear.
  Stream<List<ConversationTurn>> get changes => _controller.stream;

  /// Load (or create) the store from the app support directory.
  static Future<ConversationStore> load() async {
    final support = await getApplicationSupportDirectory();
    final file = File('${support.path}/moodpet/conversation.json');
    List<ConversationTurn> turns = <ConversationTurn>[];
    if (file.existsSync()) {
      try {
        final raw = file.readAsStringSync();
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          turns = decoded
              .whereType<Map<String, Object?>>()
              .map(ConversationTurn.fromJson)
              .toList(growable: false);
        }
      } catch (_) {
        // Corrupt file — start fresh.
      }
    }
    final store = ConversationStore._(file, turns);
    store._controller.add(turns);
    return store;
  }

  /// Append a turn. Trims to [kMaxTurns] (FIFO eviction) and persists
  /// asynchronously.
  Future<void> append(String userInput, String partnerReply) async {
    _turns.add(ConversationTurn(
      timestamp: DateTime.now(),
      userInput: userInput,
      partnerReply: partnerReply,
    ));
    if (_turns.length > kMaxTurns) {
      _turns.removeRange(0, _turns.length - kMaxTurns);
    }
    _controller.add(List<ConversationTurn>.unmodifiable(_turns));
    await _persist();
  }

  /// Drop every turn and persist.
  Future<void> clear() async {
    _turns.clear();
    _controller.add(const <ConversationTurn>[]);
    await _persist();
  }

  /// The most recent [count] turns, oldest-first — for feeding as LLM context.
  List<ConversationTurn> recent(int count) {
    if (_turns.length <= count) return List.unmodifiable(_turns);
    return List.unmodifiable(
        _turns.sublist(_turns.length - count));
  }

  Future<void> _persist() async {
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(jsonEncode(_turns));
    } catch (_) {
      // Best-effort; the in-memory list is still intact.
    }
  }

  void dispose() => _controller.close();
}

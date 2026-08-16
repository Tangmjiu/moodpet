/// 一条情绪记忆，持久化于 sqflite。
class Memory {
  const Memory({
    required this.id,
    required this.userText,
    required this.emoji,
    this.suggestion,
    required this.timestamp,
    required this.isLocal,
  });

  final int id;
  final String userText;
  final String emoji;
  final String? suggestion;
  final DateTime timestamp;

  /// true：本地规则兜底；false：PocketClaw + 云端 LLM 分析。
  final bool isLocal;

  Memory copyWith({
    int? id,
    String? userText,
    String? emoji,
    String? suggestion,
    DateTime? timestamp,
    bool? isLocal,
  }) {
    return Memory(
      id: id ?? this.id,
      userText: userText ?? this.userText,
      emoji: emoji ?? this.emoji,
      suggestion: suggestion ?? this.suggestion,
      timestamp: timestamp ?? this.timestamp,
      isLocal: isLocal ?? this.isLocal,
    );
  }

  factory Memory.fromMap(Map<String, Object?> map) => Memory(
        id: map['id'] as int,
        userText: map['user_text'] as String,
        emoji: map['emoji'] as String,
        suggestion: map['suggestion'] as String?,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
        isLocal: (map['is_local'] as int) == 1,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'user_text': userText,
        'emoji': emoji,
        'suggestion': suggestion,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'is_local': isLocal ? 1 : 0,
      };
}

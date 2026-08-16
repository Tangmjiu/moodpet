import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/memory.dart';

/// 情绪记忆仓库（sqflite）。
class MemoryRepository {
  MemoryRepository._();

  static final MemoryRepository instance = MemoryRepository._();

  static const _dbName = 'moodpet.db';
  static const _table = 'memories';
  static const _dbVersion = 1;

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null && existing.isOpen) return existing;
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, _dbName),
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE $_table (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_text TEXT NOT NULL,
  emoji TEXT NOT NULL,
  suggestion TEXT,
  timestamp INTEGER NOT NULL,
  is_local INTEGER NOT NULL DEFAULT 0
)
''');
      },
    );
    _database = db;
    return db;
  }

  Future<int> insert(Memory memory) async {
    final db = await database;
    final map = memory.toMap()..remove('id');
    return db.insert(_table, map);
  }

  Future<Memory?> insertAndReturn(Memory memory) async {
    final db = await database;
    final map = memory.toMap()..remove('id');
    final id = await db.insert(_table, map);
    return Memory(
      id: id,
      userText: memory.userText,
      emoji: memory.emoji,
      suggestion: memory.suggestion,
      timestamp: memory.timestamp,
      isLocal: memory.isLocal,
    );
  }

  Future<List<Memory>> getAll({int limit = 500}) async {
    final db = await database;
    final rows = await db.query(
      _table,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(Memory.fromMap).toList();
  }

  Future<int> deleteAll() async {
    final db = await database;
    return db.delete(_table);
  }

  Future<String> exportJson() async {
    final all = await getAll();
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'MoodPet',
      'exportedAt': DateTime.now().toIso8601String(),
      'count': all.length,
      'memories': all
          .map((m) => {
                'id': m.id,
                'userText': m.userText,
                'emoji': m.emoji,
                'suggestion': m.suggestion,
                'timestamp': m.timestamp.toIso8601String(),
                'isLocal': m.isLocal,
              })
          .toList(),
    });
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

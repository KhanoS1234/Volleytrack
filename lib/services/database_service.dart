import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/session_model.dart';
import '../models/game_event.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'volleytrack.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            jersey TEXT NOT NULL,
            playerName TEXT NOT NULL,
            date TEXT NOT NULL,
            durationSeconds INTEGER NOT NULL,
            hits INTEGER NOT NULL,
            blocks INTEGER NOT NULL,
            points INTEGER NOT NULL,
            eventsJson TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<int> saveSession(SessionModel session) async {
    final db = await database;
    final eventsJson = jsonEncode(session.events.map((e) => e.toMap()).toList());
    final map = session.toMap();
    map['eventsJson'] = eventsJson;
    return db.insert('sessions', map);
  }

  Future<List<SessionModel>> getAllSessions() async {
    final db = await database;
    final rows = await db.query('sessions', orderBy: 'date DESC');
    return rows.map((row) {
      final eventsList = (jsonDecode(row['eventsJson'] as String) as List)
          .map((e) => GameEvent.fromMap(e as Map<String, dynamic>))
          .toList();
      return SessionModel(
        id: row['id'] as int,
        jersey: row['jersey'] as String,
        playerName: row['playerName'] as String,
        date: DateTime.parse(row['date'] as String),
        durationSeconds: row['durationSeconds'] as int,
        hits: row['hits'] as int,
        blocks: row['blocks'] as int,
        points: row['points'] as int,
        events: eventsList,
      );
    }).toList();
  }

  Future<void> deleteSession(int id) async {
    final db = await database;
    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
  }
}

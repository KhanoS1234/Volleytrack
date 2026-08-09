import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/game_event.dart';
import '../models/session_model.dart';
import '../models/team_model.dart';

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
    final path   = join(dbPath, 'volleytrack.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS teams (
              id        INTEGER PRIMARY KEY AUTOINCREMENT,
              name      TEXT NOT NULL,
              createdAt TEXT NOT NULL,
              players   TEXT NOT NULL
            )
          ''');
        }
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE sessions (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        jersey           TEXT    NOT NULL,
        playerName       TEXT    NOT NULL,
        date             TEXT    NOT NULL,
        durationSeconds  INTEGER NOT NULL,
        hits             INTEGER NOT NULL,
        blocks           INTEGER NOT NULL,
        points           INTEGER NOT NULL,
        eventsJson       TEXT    NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE teams (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        name      TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        players   TEXT NOT NULL
      )
    ''');
  }

  // ── TEAM OPERATIONS ──────────────────────────────────────────────────────

  Future<int> saveTeam(TeamModel team) async {
    final db = await database;
    if (team.id != null) {
      await db.update('teams', team.toMap(),
          where: 'id = ?', whereArgs: [team.id]);
      return team.id!;
    }
    return db.insert('teams', team.toMap());
  }

  Future<List<TeamModel>> getAllTeams() async {
    final db   = await database;
    final rows = await db.query('teams', orderBy: 'createdAt DESC');
    return rows.map((r) => TeamModel.fromMap(r)).toList();
  }

  Future<TeamModel?> getTeam(int id) async {
    final db   = await database;
    final rows = await db.query('teams', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return TeamModel.fromMap(rows.first);
  }

  Future<void> deleteTeam(int id) async {
    final db = await database;
    await db.delete('teams', where: 'id = ?', whereArgs: [id]);
  }

  // ── SESSION OPERATIONS ───────────────────────────────────────────────────

  Future<int> saveSession(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('sessions', data);
  }

  Future<List<SessionModel>> getAllSessions() async {
    final db   = await database;
    final rows = await db.query('sessions', orderBy: 'date DESC');
    return rows.map((row) {
      final eventsList =
          (jsonDecode(row['eventsJson'] as String) as List)
              .map((e) => GameEvent.fromMap(e as Map<String, dynamic>))
              .toList();
      return SessionModel(
        id:              row['id']              as int,
        jersey:          row['jersey']          as String,
        playerName:      row['playerName']      as String,
        date:            DateTime.parse(row['date'] as String),
        durationSeconds: row['durationSeconds'] as int,
        hits:            row['hits']            as int,
        blocks:          row['blocks']          as int,
        points:          row['points']          as int,
        events:          eventsList,
      );
    }).toList();
  }
}

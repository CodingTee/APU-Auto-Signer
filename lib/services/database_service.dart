import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/student.dart';

/// Local SQLite database service for managing student accounts.
class DatabaseService {
  static const String _dbName = 'apu_auto_signer.db';
  static const String _tableName = 'students';
  static const int _dbVersion = 1;

  Database? _db;

  /// Initialize the database.
  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL UNIQUE,
            token TEXT NOT NULL,
            display_name TEXT NOT NULL,
            created_at TEXT NOT NULL,
            last_used_at TEXT,
            is_active INTEGER NOT NULL DEFAULT 1
          )
        ''');
      },
    );
  }

  Database get _database {
    if (_db == null) {
      throw StateError('Database not initialized. Call init() first.');
    }
    return _db!;
  }

  /// Insert a new student into the database.
  Future<int> insertStudent(Student student) async {
    return await _database.insert(
      _tableName,
      student.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all active students.
  Future<List<Student>> getAllStudents() async {
    final maps = await _database.query(
      _tableName,
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'display_name ASC',
    );
    return maps.map((m) => Student.fromMap(m)).toList();
  }

  /// Get a student by user_id.
  Future<Student?> getStudentByUserId(String userId) async {
    final maps = await _database.query(
      _tableName,
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Student.fromMap(maps.first);
  }

  /// Update a student's token (e.g. after re-authorization).
  Future<int> updateToken(String userId, String newToken) async {
    return await _database.update(
      _tableName,
      {'token': newToken},
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// Update a student's display name (nickname).
  Future<int> updateDisplayName(String userId, String newName) async {
    return await _database.update(
      _tableName,
      {'display_name': newName},
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// Update last used timestamp.
  Future<int> updateLastUsed(String userId) async {
    return await _database.update(
      _tableName,
      {'last_used_at': DateTime.now().toIso8601String()},
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// Delete a student by ID.
  Future<int> deleteStudent(int id) async {
    return await _database.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deactivate a student (soft delete).
  Future<int> deactivateStudent(int id) async {
    return await _database.update(
      _tableName,
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Close the database connection.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

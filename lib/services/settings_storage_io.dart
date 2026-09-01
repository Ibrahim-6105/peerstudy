// SQLite-backed device settings for the native PeerStudy applications.

import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

// The previous implementation used this SharedPreferences key. It is read
// once during migration, while new Android/iOS writes go to SQLite.
const String _legacyBlobKey = 'peerstudySettingsV1';

class SettingsStorage {
  SettingsStorage._();

  static final SettingsStorage instance = SettingsStorage._();

  Database? _database;

  // PeerStudy ships Supabase mobile clients on Android and iOS. Desktop test
  // runners keep the lightweight plugin fallback because sqflite needs an
  // extra desktop factory that the product does not otherwise use.
  bool get _usesSqlite => Platform.isAndroid || Platform.isIOS;

  Future<Database> _openDatabase() async {
    if (_database != null) return _database!;
    final folder = await getDatabasesPath();
    final path = '$folder${Platform.pathSeparator}peerstudy_settings.db';
    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE app_settings (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            settings_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }

  // Reads the one complete atomic JSON snapshot.
  Future<String?> readBlob() async {
    if (!_usesSqlite) {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_legacyBlobKey);
    }
    final database = await _openDatabase();
    final rows = await database.query(
      'app_settings',
      columns: const <String>['settings_json'],
      where: 'id = ?',
      whereArgs: const <Object>[1],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['settings_json'] as String?;
  }

  // Replaces the single row inside one SQLite transaction-safe statement.
  Future<bool> writeBlob(String value) async {
    if (!_usesSqlite) {
      final preferences = await SharedPreferences.getInstance();
      return preferences.setString(_legacyBlobKey, value);
    }
    final database = await _openDatabase();
    final rowId = await database.insert('app_settings', <String, Object?>{
      'id': 1,
      'settings_json': value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return rowId == 1;
  }

  // Supplies old plugin values only when no SQLite snapshot exists yet.
  Future<Map<String, Object?>> readLegacyValues() async {
    final preferences = await SharedPreferences.getInstance();
    return <String, Object?>{
      'blob': preferences.getString(_legacyBlobKey),
      'themeMode': preferences.getString('themeMode'),
      'lastAreaId': preferences.getString('lastAreaId'),
      'lastDepartmentId': preferences.getString('lastDepartmentId'),
      'lastSubjectId': preferences.getString('lastSubjectId'),
    };
  }
}

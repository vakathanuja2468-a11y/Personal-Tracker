
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

class StorageHelper {
  StorageHelper._();

  static const String _databaseName = 'personal_tracker.db';
  static const String _tableName = 'tracker_records';
  static const String _legacyPreferencesKey = 'personal_tracker_records';

  static Database? _database;
  static bool _initialized = false;

  /// Initializes the appropriate database implementation.
  static Future<void> _initializeDatabaseFactory() async {
    if (_initialized) return;

    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    }

    _initialized = true;
  }

  /// Opens the database and creates the records table if needed.
  static Future<Database> get _db async {
    await _initializeDatabaseFactory();

    if (_database != null) {
      return _database!;
    }

    final String databasePath;

    if (kIsWeb) {
      // Web databases are stored in browser IndexedDB.
      databasePath = _databaseName;
    } else {
      final directory = await getDatabasesPath();
      databasePath = p.join(directory, _databaseName);
    }

    _database = await openDatabase(
      databasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            category TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            amount REAL NOT NULL DEFAULT 0,
            completed INTEGER NOT NULL DEFAULT 0,
            completion_dates TEXT NOT NULL DEFAULT '[]',
            updated_at TEXT,
            record_json TEXT NOT NULL
          )
        ''');
      },
    );

    await _migrateLegacyPreferences(_database!);

    return _database!;
  }

  /// Loads all saved records.
  static Future<List<Map<String, dynamic>>> loadRecords() async {
    final db = await _db;

    final rows = await db.query(
      _tableName,
      orderBy: 'id ASC',
    );

    return rows.map((row) {
      final decoded = jsonDecode(row['record_json'] as String);

      return Map<String, dynamic>.from(decoded as Map);
    }).toList();
  }

  /// Saves the complete list of records in a transaction.
  static Future<void> saveRecords(
    List<Map<String, dynamic>> records,
  ) async {
    final db = await _db;

    await db.transaction((txn) async {
      await txn.delete(_tableName);

      final batch = txn.batch();

      for (final source in records) {
        final record = Map<String, dynamic>.from(source);

        final title = record['title']?.toString().trim();
        final category = record['category']?.toString().trim();
        final description = record['description']?.toString() ?? '';

        final amount =
            double.tryParse(record['amount']?.toString() ?? '') ?? 0.0;

        final completed = record['completed'] == true ? 1 : 0;

        final dates = record['completionDates'];
        final completionDates =
            dates is List ? dates : <dynamic>[];

        batch.insert(_tableName, {
          'title': (title == null || title.isEmpty)
              ? 'Untitled'
              : title,
          'category': (category == null || category.isEmpty)
              ? 'Activity'
              : category,
          'description': description,
          'amount': amount,
          'completed': completed,
          'completion_dates': jsonEncode(completionDates),
          'updated_at': record['updatedAt']?.toString(),
          'record_json': jsonEncode(record),
        });
      }

      await batch.commit(noResult: true);
    });
  }

  /// Migrates records saved by an older SharedPreferences version.
  static Future<void> _migrateLegacyPreferences(
    Database db,
  ) async {
    final count = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM $_tableName',
          ),
        ) ??
        0;

    if (count > 0) return;

    final prefs = await SharedPreferences.getInstance();
    final legacyJson = prefs.getString(_legacyPreferencesKey);

    if (legacyJson == null || legacyJson.isEmpty) return;

    try {
      final decoded = jsonDecode(legacyJson) as List<dynamic>;

      final records = decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      await db.transaction((txn) async {
        final batch = txn.batch();

        for (final record in records) {
          final title = record['title']?.toString().trim();
          final category = record['category']?.toString().trim();
          final description = record['description']?.toString() ?? '';

          final amount =
              double.tryParse(record['amount']?.toString() ?? '') ?? 0.0;

          final dates = record['completionDates'];

          batch.insert(_tableName, {
            'title': (title == null || title.isEmpty)
                ? 'Untitled'
                : title,
            'category': (category == null || category.isEmpty)
                ? 'Activity'
                : category,
            'description': description,
            'amount': amount,
            'completed': record['completed'] == true ? 1 : 0,
            'completion_dates': jsonEncode(
              dates is List ? dates : <dynamic>[],
            ),
            'updated_at': record['updatedAt']?.toString(),
            'record_json': jsonEncode(record),
          });
        }

        await batch.commit(noResult: true);
      });

      await prefs.remove(_legacyPreferencesKey);
    } catch (e, stackTrace) {
      debugPrint('Legacy data migration failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// Closes the database connection if needed.
  static Future<void> closeDatabase() async {
    final db = _database;
    if (db == null) return;

    await db.close();
    _database = null;
  }
}

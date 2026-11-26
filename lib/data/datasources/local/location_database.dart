import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/location_record.dart';

/// SQLite persistence for location samples.
///
/// Acts as an offline-first write-ahead queue: every GPS fix is inserted
/// immediately as [SyncStatus.pending], then the sync service drains the
/// queue when connectivity is available.
class LocationDatabase {
  LocationDatabase({DatabaseFactory? databaseFactory, String? databasePath})
      : _databaseFactory = databaseFactory ?? databaseFactoryFromSqflite,
        _databasePath = databasePath;

  /// Allows injecting [sqflite_common_ffi] in unit tests.
  final DatabaseFactory _databaseFactory;
  final String? _databasePath;

  Database? _db;

  static DatabaseFactory get databaseFactoryFromSqflite => databaseFactory;

  Future<Database> get database async {
    // sqflite close() is process-wide for a path: the background isolate must
    // not permanently invalidate the UI isolate's cached handle.
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = _databasePath ??
        p.join(await getDatabasesPath(), 'location_tracker.db');

    return _databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE location_records (
              id TEXT PRIMARY KEY NOT NULL,
              latitude REAL NOT NULL,
              longitude REAL NOT NULL,
              accuracy REAL NOT NULL,
              recorded_at TEXT NOT NULL,
              sync_status TEXT NOT NULL,
              synced_at TEXT,
              retry_count INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_location_sync_status ON location_records(sync_status)',
          );
        },
      ),
    );
  }

  Future<void> insert(LocationRecord record) async {
    final db = await database;
    await db.insert(
      'location_records',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<LocationRecord>> getAll({int limit = 100}) async {
    final db = await database;
    final rows = await db.query(
      'location_records',
      orderBy: 'recorded_at DESC',
      limit: limit,
    );
    return rows.map(LocationRecord.fromMap).toList();
  }

  Future<int> countAll() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM location_records',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<LocationRecord>> getPending({int limit = 50}) async {
    final db = await database;
    final rows = await db.query(
      'location_records',
      where: 'sync_status IN (?, ?)',
      whereArgs: [SyncStatus.pending.name, SyncStatus.failed.name],
      orderBy: 'recorded_at ASC',
      limit: limit,
    );
    return rows.map(LocationRecord.fromMap).toList();
  }

  Future<int> countByStatus(SyncStatus status) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM location_records WHERE sync_status = ?',
      [status.name],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> markSyncing(String id) async {
    final db = await database;
    await db.update(
      'location_records',
      {'sync_status': SyncStatus.syncing.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markSynced(String id, {DateTime? syncedAt}) async {
    final db = await database;
    await db.update(
      'location_records',
      {
        'sync_status': SyncStatus.synced.name,
        'synced_at': (syncedAt ?? DateTime.now().toUtc()).toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markFailed(String id) async {
    final db = await database;
    await db.rawUpdate(
      '''
      UPDATE location_records
      SET sync_status = ?, retry_count = retry_count + 1
      WHERE id = ?
      ''',
      [SyncStatus.failed.name, id],
    );
  }

  Future<void> resetStuckSyncing() async {
    final db = await database;
    await db.update(
      'location_records',
      {'sync_status': SyncStatus.pending.name},
      where: 'sync_status = ?',
      whereArgs: [SyncStatus.syncing.name],
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

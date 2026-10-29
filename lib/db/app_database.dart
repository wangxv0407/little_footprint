import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/baby_info.dart';
import '../models/growth_metric.dart';
import '../models/growth_record.dart';
import '../models/media_item.dart';
import '../models/sync_log.dart';

/// 本地 SQLite 数据库单例，负责全部表的初始化与读写。
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'little_footprint.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE baby_info (
        id INTEGER PRIMARY KEY,
        baby_name TEXT NOT NULL DEFAULT '',
        birth_date TEXT NOT NULL,
        device_role TEXT NOT NULL DEFAULT 'husband'
      )
    ''');
    await db.execute('''
      CREATE TABLE growth_record (
        uuid TEXT PRIMARY KEY,
        record_time TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        tags TEXT NOT NULL DEFAULT '',
        create_device TEXT NOT NULL DEFAULT 'husband',
        last_modify_ts INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE media_item (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        record_uuid TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_type TEXT NOT NULL,
        local_relative_path TEXT NOT NULL,
        file_md5 TEXT NOT NULL DEFAULT '',
        file_size INTEGER NOT NULL DEFAULT 0,
        is_origin INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (record_uuid) REFERENCES growth_record(uuid) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_media_record ON media_item(record_uuid)
    ''');
    await db.execute('''
      CREATE TABLE growth_metric (
        uuid TEXT PRIMARY KEY,
        metric_time TEXT NOT NULL,
        height REAL NOT NULL DEFAULT 0,
        weight REAL NOT NULL DEFAULT 0,
        head_circum REAL NOT NULL DEFAULT 0,
        last_modify_ts INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        peer_ip TEXT NOT NULL DEFAULT '',
        sync_ts INTEGER NOT NULL,
        summary TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  // ---------- 会话级便捷访问 ----------
  Future<Database> get db => database;

  // ================= Baby Info =================
  Future<BabyInfo?> getBabyInfo() async {
    final db = await database;
    final list = await db.query('baby_info', limit: 1);
    if (list.isEmpty) return null;
    return BabyInfo.fromMap(list.first);
  }

  Future<void> saveBabyInfo(BabyInfo info) async {
    final db = await database;
    await db.insert(
      'baby_info',
      info.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ================= Growth Record =================
  Future<void> upsertGrowthRecord(GrowthRecord r) async {
    final db = await database;
    await db.insert(
      'growth_record',
      r.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<GrowthRecord?> getGrowthRecord(String uuid) async {
    final db = await database;
    final list = await db.query('growth_record', where: 'uuid = ?', whereArgs: [uuid]);
    if (list.isEmpty) return null;
    return GrowthRecord.fromMap(list.first);
  }

  /// 按事件时间倒序返回全部非删除记录
  Future<List<GrowthRecord>> getRecords() async {
    final db = await database;
    final list = await db.query(
      'growth_record',
      where: 'is_deleted = 0',
      orderBy: 'record_time DESC',
    );
    return list.map(GrowthRecord.fromMap).toList();
  }

  /// 获取自某时间戳之后变更的记录（含软删除），用于增量同步
  Future<List<GrowthRecord>> getRecordsChangedSince(int sinceTs) async {
    final db = await database;
    final list = await db.query(
      'growth_record',
      where: 'last_modify_ts > ?',
      whereArgs: [sinceTs],
    );
    return list.map(GrowthRecord.fromMap).toList();
  }

  Future<int> deleteRecordSoft(String uuid) async {
    final db = await database;
    return db.update(
      'growth_record',
      {'is_deleted': 1, 'last_modify_ts': DateTime.now().millisecondsSinceEpoch},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  // ================= Media Item =================
  Future<int> insertMedia(MediaItem m) async {
    final db = await database;
    return db.insert('media_item', m.toMap());
  }

  Future<List<MediaItem>> getMediaForRecord(String recordUuid,
      {bool onlySyncable = false}) async {
    final db = await database;
    var where = 'record_uuid = ?';
    final args = <String>[recordUuid];
    if (onlySyncable) {
      where += ' AND is_origin = 0';
    }
    final list = await db.query('media_item', where: where, whereArgs: args);
    return list.map(MediaItem.fromMap).toList();
  }

  Future<void> deleteMediaById(int id) async {
    final db = await database;
    await db.delete('media_item', where: 'id = ?', whereArgs: [id]);
  }

  // ================= Growth Metric =================
  Future<void> upsertGrowthMetric(GrowthMetric m) async {
    final db = await database;
    await db.insert(
      'growth_metric',
      m.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<GrowthMetric>> getMetrics() async {
    final db = await database;
    final list = await db.query(
      'growth_metric',
      where: 'is_deleted = 0',
      orderBy: 'metric_time ASC',
    );
    return list.map(GrowthMetric.fromMap).toList();
  }

  Future<List<GrowthMetric>> getMetricsChangedSince(int sinceTs) async {
    final db = await database;
    final list = await db.query(
      'growth_metric',
      where: 'last_modify_ts > ?',
      whereArgs: [sinceTs],
    );
    return list.map(GrowthMetric.fromMap).toList();
  }

  Future<int> deleteMetricSoft(String uuid) async {
    final db = await database;
    return db.update(
      'growth_metric',
      {'is_deleted': 1, 'last_modify_ts': DateTime.now().millisecondsSinceEpoch},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  // ================= Sync Log =================
  Future<void> insertSyncLog(SyncLog log) async {
    final db = await database;
    await db.insert('sync_log', log.toMap());
  }

  /// 最近一次同步完成时间戳（增量同步起点）
  Future<int> getLastSyncTs() async {
    final db = await database;
    final list = await db.query('sync_log', orderBy: 'sync_ts DESC', limit: 1);
    if (list.isEmpty) return 0;
    return SyncLog.fromMap(list.first).syncTs;
  }

  Future<List<SyncLog>> getSyncLogs({int limit = 20}) async {
    final db = await database;
    final list = await db.query('sync_log', orderBy: 'sync_ts DESC', limit: limit);
    return list.map(SyncLog.fromMap).toList();
  }
}

import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../data/milestone_seed.dart';
import '../models/baby_info.dart';
import '../models/growth_metric.dart';
import '../models/growth_record.dart';
import '../models/media_item.dart';
import '../models/milestone_def.dart';
import '../models/record_type.dart';
import '../models/sync_log.dart';

/// 时间轴筛选条件
enum RecordFilter { all, photo, audio, video, milestone, favorite }

/// 本地 SQLite 数据库单例。
///
/// v2 起支持多宝宝：所有业务表通过 `baby_id` 归属，`baby_info.is_active`
/// 标记当前查看的宝宝；本机身份（爸爸/妈妈）从 baby_info 迁到 app_setting，
/// 因为它是设备属性而非宝宝属性。
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'little_footprint.db';
  static const _dbVersion = 2;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    // 升级前先备份，失败可回滚（PRD FR-101）
    await _backupBeforeUpgrade(path);

    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // ==================== 迁移 ====================

  /// 检测 user_version < 2 且数据库已存在时，复制一份 `.bak.v1`。
  /// 备份失败不阻断启动——迁移本身是幂等的，但会记录日志。
  Future<void> _backupBeforeUpgrade(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return;

      final probe = await openReadOnlyDatabase(path);
      final v = await probe.getVersion();
      await probe.close();
      if (v >= _dbVersion) return;

      final bak = File('$path.bak.v1');
      if (await bak.exists()) return; // 已备份过，不覆盖
      await f.copy(bak.path);
      // ignore: avoid_print
      print('[db] 已备份到 ${bak.path} (v$v)');
    } catch (e) {
      // ignore: avoid_print
      print('[db] 升级前备份失败: $e');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createV2Schema(db);
    await _seedMilestones(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _migrateV1ToV2(db);
    }
  }

  /// 迁移必须幂等：以实际表结构为准，重复执行不产生副作用。
  Future<void> _migrateV1ToV2(Database db) async {
    // 1) 配置表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_setting (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL DEFAULT ''
      )
    ''');

    // 2) 读出旧的本机身份，迁到 app_setting
    String legacyRole = 'husband';
    final exists = await _tableExists(db, 'baby_info');
    if (exists) {
      final rows = await db.query('baby_info', limit: 1);
      if (rows.isNotEmpty) {
        legacyRole = (rows.first['device_role'] as String?) ?? 'husband';
      }
    }
    await db.insert(
      'app_setting',
      {
        'key': 'device_role',
        'value': legacyRole == 'wife' ? 'partner' : 'owner',
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    // 3) 重建 baby_info（SQLite 不支持改主键，只能 rename + create + copy）
    if (exists) {
      await db.execute('ALTER TABLE baby_info RENAME TO baby_info_v1');
      await _createBabyInfo(db);
      await db.execute('''
        INSERT INTO baby_info (id, baby_name, birth_date, avatar_path, gender, is_active, last_modify_ts)
        SELECT id, baby_name, birth_date, '', 0, 1, 0 FROM baby_info_v1
      ''');
      // 兜底：旧表为空时补一条占位，避免 App 进不去
      final cnt = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM baby_info'),
          ) ??
          0;
      if (cnt == 0) {
        await db.insert('baby_info', {
          'baby_name': '宝宝',
          'birth_date': BabyInfo.fmtDate(DateTime.now()),
        });
      }
      await db.execute('DROP TABLE baby_info_v1');
    } else {
      await _createBabyInfo(db);
    }

    // 4) growth_record 新字段
    await _addColumnIfMissing(db, 'growth_record', 'baby_id', 'INTEGER NOT NULL DEFAULT 1');
    await _addColumnIfMissing(db, 'growth_record', 'record_type', "TEXT NOT NULL DEFAULT 'diary'");
    await _addColumnIfMissing(db, 'growth_record', 'milestone_code', "TEXT NOT NULL DEFAULT ''");
    await _addColumnIfMissing(db, 'growth_record', 'is_favorite', 'INTEGER NOT NULL DEFAULT 0');

    // 5) growth_metric 新字段
    await _addColumnIfMissing(db, 'growth_metric', 'baby_id', 'INTEGER NOT NULL DEFAULT 1');

    // 6) 里程碑库
    await db.execute('''
      CREATE TABLE IF NOT EXISTS milestone_def (
        code       TEXT PRIMARY KEY,
        category   TEXT    NOT NULL,
        name       TEXT    NOT NULL,
        month_min  INTEGER NOT NULL DEFAULT 0,
        month_max  INTEGER NOT NULL DEFAULT 36,
        is_preset  INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _seedMilestones(db);

    // 7) 旧身份值规范化
    await db.execute("UPDATE growth_record SET create_device = 'owner' WHERE create_device = 'husband'");
    await db.execute("UPDATE growth_record SET create_device = 'partner' WHERE create_device = 'wife'");

    // 8) 索引
    await _createIndexes(db);

    await db.insert(
      'app_setting',
      {'key': 'migrated_to_v2', 'value': '1'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // 9) 行数校验：不通过则抛错，让 openDatabase 回滚事务
    await _verifyRowCounts(db);
  }

  Future<void> _verifyRowCounts(Database db) async {
    final records = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM growth_record'),
        ) ??
        0;
    final babies = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM baby_info'),
        ) ??
        0;
    if (babies == 0) {
      throw StateError('迁移校验失败：baby_info 为空');
    }
    // ignore: avoid_print
    print('[db] 迁移完成：宝宝 $babies 个，记录 $records 条');
  }

  Future<bool> _tableExists(Database db, String name) async {
    final r = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [name],
    );
    return r.isNotEmpty;
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String ddl,
  ) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    final has = cols.any((c) => c['name'] == column);
    if (!has) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $ddl');
    }
  }

  Future<void> _createBabyInfo(Database db) async {
    await db.execute('''
      CREATE TABLE baby_info (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        baby_name      TEXT    NOT NULL DEFAULT '',
        birth_date     TEXT    NOT NULL,
        avatar_path    TEXT    NOT NULL DEFAULT '',
        gender         INTEGER NOT NULL DEFAULT 0,
        is_active      INTEGER NOT NULL DEFAULT 1,
        last_modify_ts INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_record_baby_time ON growth_record(baby_id, is_deleted, record_time DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_record_type ON growth_record(record_type)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_record_ms ON growth_record(milestone_code)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_metric_baby_time ON growth_metric(baby_id, is_deleted, metric_time)');
  }

  Future<void> _seedMilestones(Database db) async {
    final batch = db.batch();
    for (final m in kMilestoneSeed) {
      batch.insert('milestone_def', m.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  /// 全新安装时的完整 v2 结构
  Future<void> _createV2Schema(Database db) async {
    await _createBabyInfo(db);

    await db.execute('''
      CREATE TABLE growth_record (
        uuid           TEXT PRIMARY KEY,
        baby_id        INTEGER NOT NULL DEFAULT 1,
        record_time    TEXT    NOT NULL,
        content        TEXT    NOT NULL DEFAULT '',
        tags           TEXT    NOT NULL DEFAULT '',
        record_type    TEXT    NOT NULL DEFAULT 'diary',
        milestone_code TEXT    NOT NULL DEFAULT '',
        is_favorite    INTEGER NOT NULL DEFAULT 0,
        create_device  TEXT    NOT NULL DEFAULT 'owner',
        last_modify_ts INTEGER NOT NULL DEFAULT 0,
        is_deleted     INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE media_item (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        record_uuid         TEXT    NOT NULL,
        file_name           TEXT    NOT NULL,
        file_type           TEXT    NOT NULL,
        local_relative_path TEXT    NOT NULL,
        file_md5            TEXT    NOT NULL DEFAULT '',
        file_size           INTEGER NOT NULL DEFAULT 0,
        is_origin           INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (record_uuid) REFERENCES growth_record(uuid) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_media_record ON media_item(record_uuid)');

    await db.execute('''
      CREATE TABLE growth_metric (
        uuid           TEXT PRIMARY KEY,
        baby_id        INTEGER NOT NULL DEFAULT 1,
        metric_time    TEXT    NOT NULL,
        height         REAL    NOT NULL DEFAULT 0,
        weight         REAL    NOT NULL DEFAULT 0,
        head_circum    REAL    NOT NULL DEFAULT 0,
        last_modify_ts INTEGER NOT NULL DEFAULT 0,
        is_deleted     INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_log (
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        peer_ip TEXT    NOT NULL DEFAULT '',
        sync_ts INTEGER NOT NULL,
        summary TEXT    NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE milestone_def (
        code       TEXT PRIMARY KEY,
        category   TEXT    NOT NULL,
        name       TEXT    NOT NULL,
        month_min  INTEGER NOT NULL DEFAULT 0,
        month_max  INTEGER NOT NULL DEFAULT 36,
        is_preset  INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE app_setting (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL DEFAULT ''
      )
    ''');

    await _createIndexes(db);
  }

  // ==================== 配置 KV ====================

  Future<String?> getSetting(String key) async {
    final db = await database;
    final r = await db.query('app_setting', where: 'key = ?', whereArgs: [key], limit: 1);
    if (r.isEmpty) return null;
    return r.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_setting',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 本机身份：owner / partner
  Future<String> getDeviceRole() async => (await getSetting('device_role')) ?? 'owner';

  Future<void> setDeviceRole(String role) => setSetting('device_role', role);

  static String deviceRoleLabel(String role) =>
      role == 'partner' ? '妈妈' : '爸爸';

  // ==================== 宝宝 ====================

  Future<List<BabyInfo>> getBabies() async {
    final db = await database;
    final list = await db.query('baby_info', orderBy: 'id ASC');
    return list.map(BabyInfo.fromMap).toList();
  }

  /// 当前选中的宝宝；没有任何宝宝时返回 null
  Future<BabyInfo?> getActiveBaby() async {
    final db = await database;
    final active = await db.query('baby_info', where: 'is_active = 1', limit: 1);
    if (active.isNotEmpty) return BabyInfo.fromMap(active.first);
    final any = await db.query('baby_info', orderBy: 'id ASC', limit: 1);
    if (any.isEmpty) return null;
    return BabyInfo.fromMap(any.first);
  }

  /// 兼容旧调用
  Future<BabyInfo?> getBabyInfo() => getActiveBaby();

  Future<BabyInfo?> getBabyById(int id) async {
    final db = await database;
    final r = await db.query('baby_info', where: 'id = ?', whereArgs: [id], limit: 1);
    if (r.isEmpty) return null;
    return BabyInfo.fromMap(r.first);
  }

  Future<int> insertBaby(BabyInfo info) async {
    final db = await database;
    final map = info.toMap()..remove('id');
    map['last_modify_ts'] = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('baby_info', map);
    // 第一个宝宝自动成为当前
    final cnt = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM baby_info')) ?? 0;
    if (cnt == 1) await setActiveBaby(id);
    return id;
  }

  Future<void> updateBaby(BabyInfo info) async {
    final db = await database;
    await db.update(
      'baby_info',
      info.copyWith(lastModifyTs: DateTime.now().millisecondsSinceEpoch).toMap(),
      where: 'id = ?',
      whereArgs: [info.id],
    );
  }

  Future<void> setActiveBaby(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('baby_info', {'is_active': 0});
      await txn.update('baby_info', {'is_active': 1}, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<int> countRecordsOfBaby(int babyId) async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM growth_record WHERE baby_id = ? AND is_deleted = 0',
          [babyId],
        )) ??
        0;
  }

  /// 删除宝宝及其全部记录与媒体（物理删除，由调用方做二次确认）
  Future<void> deleteBabyCascade(int babyId) async {
    final db = await database;
    await db.transaction((txn) async {
      final uuids = await txn.query(
        'growth_record',
        columns: ['uuid'],
        where: 'baby_id = ?',
        whereArgs: [babyId],
      );
      for (final row in uuids) {
        await txn.delete('media_item', where: 'record_uuid = ?', whereArgs: [row['uuid']]);
      }
      await txn.delete('growth_record', where: 'baby_id = ?', whereArgs: [babyId]);
      await txn.delete('growth_metric', where: 'baby_id = ?', whereArgs: [babyId]);
      await txn.delete('baby_info', where: 'id = ?', whereArgs: [babyId]);
    });
  }

  // ==================== 记录 ====================

  Future<void> upsertGrowthRecord(GrowthRecord r) async {
    final db = await database;
    await db.insert('growth_record', r.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<GrowthRecord?> getGrowthRecord(String uuid) async {
    final db = await database;
    final list = await db.query('growth_record', where: 'uuid = ?', whereArgs: [uuid]);
    if (list.isEmpty) return null;
    return GrowthRecord.fromMap(list.first);
  }

  /// 按宝宝取记录，支持筛选与分页
  Future<List<GrowthRecord>> getRecords(
    int babyId, {
    RecordFilter filter = RecordFilter.all,
    int? limit,
    int offset = 0,
  }) async {
    final db = await database;
    final where = StringBuffer('r.baby_id = ? AND r.is_deleted = 0');
    final args = <Object?>[babyId];

    switch (filter) {
      case RecordFilter.photo:
        where.write(" AND EXISTS (SELECT 1 FROM media_item m WHERE m.record_uuid = r.uuid AND m.file_type = 'image')");
      case RecordFilter.audio:
        where.write(" AND EXISTS (SELECT 1 FROM media_item m WHERE m.record_uuid = r.uuid AND m.file_type = 'audio')");
      case RecordFilter.video:
        where.write(" AND EXISTS (SELECT 1 FROM media_item m WHERE m.record_uuid = r.uuid AND m.file_type = 'video')");
      case RecordFilter.milestone:
        where.write(" AND r.record_type = '${RecordType.milestone}'");
      case RecordFilter.favorite:
        where.write(' AND r.is_favorite = 1');
      case RecordFilter.all:
        break;
    }

    final sql = StringBuffer('SELECT r.* FROM growth_record r WHERE $where ORDER BY r.record_time DESC');
    if (limit != null) {
      sql.write(' LIMIT $limit OFFSET $offset');
    }
    final list = await db.rawQuery(sql.toString(), args);
    return list.map(GrowthRecord.fromMap).toList();
  }

  /// 一次性取出该宝宝所有记录的媒体，按记录分组。
  ///
  /// 替代旧实现「循环里逐条查 media_item」的 N+1 写法
  /// （1000 条记录会发起 1001 次查询）。
  Future<Map<String, List<MediaItem>>> getMediaMapForBaby(int babyId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT m.* FROM media_item m
      WHERE m.record_uuid IN (
        SELECT uuid FROM growth_record WHERE baby_id = ? AND is_deleted = 0
      )
      ORDER BY m.id ASC
    ''', [babyId]);

    final map = <String, List<MediaItem>>{};
    for (final row in rows) {
      final item = MediaItem.fromMap(row);
      map.putIfAbsent(item.recordUuid, () => []).add(item);
    }
    return map;
  }

  /// 关键词搜索：正文 / 标签 / 里程碑名
  Future<List<GrowthRecord>> searchRecords(
    int babyId,
    String keyword, {
    RecordFilter filter = RecordFilter.all,
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await database;
    final kw = '%${keyword.trim()}%';
    final where = StringBuffer('r.baby_id = ? AND r.is_deleted = 0');
    final args = <Object?>[babyId];

    if (keyword.trim().isNotEmpty) {
      where.write(''' AND (
        r.content LIKE ?
        OR r.tags LIKE ?
        OR r.milestone_code IN (SELECT code FROM milestone_def WHERE name LIKE ?)
      )''');
      args..add(kw)..add(kw)..add(kw);
    }
    if (from != null) {
      where.write(' AND r.record_time >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.write(' AND r.record_time <= ?');
      args.add(to.toIso8601String());
    }
    switch (filter) {
      case RecordFilter.milestone:
        where.write(" AND r.record_type = '${RecordType.milestone}'");
      case RecordFilter.favorite:
        where.write(' AND r.is_favorite = 1');
      case RecordFilter.photo:
        where.write(" AND EXISTS (SELECT 1 FROM media_item m WHERE m.record_uuid = r.uuid AND m.file_type = 'image')");
      case RecordFilter.video:
        where.write(" AND EXISTS (SELECT 1 FROM media_item m WHERE m.record_uuid = r.uuid AND m.file_type = 'video')");
      case RecordFilter.audio:
        where.write(" AND EXISTS (SELECT 1 FROM media_item m WHERE m.record_uuid = r.uuid AND m.file_type = 'audio')");
      case RecordFilter.all:
        break;
    }

    final rows = await db.rawQuery(
      'SELECT r.* FROM growth_record r WHERE $where ORDER BY r.record_time DESC LIMIT 200',
      args,
    );
    return rows.map(GrowthRecord.fromMap).toList();
  }

  Future<int> toggleFavorite(String uuid, bool favorite) async {
    final db = await database;
    return db.update(
      'growth_record',
      {
        'is_favorite': favorite ? 1 : 0,
        'last_modify_ts': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
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

  /// 标签使用频次，用于搜索页「按标签查找」
  Future<List<(String, int)>> getTagStats(int babyId, {int limit = 12}) async {
    final db = await database;
    final rows = await db.query(
      'growth_record',
      columns: ['tags'],
      where: 'baby_id = ? AND is_deleted = 0 AND tags != ?',
      whereArgs: [babyId, ''],
    );
    final counter = <String, int>{};
    for (final r in rows) {
      final raw = (r['tags'] as String? ?? '');
      for (final t in raw.split(',')) {
        final tag = t.trim();
        if (tag.isEmpty) continue;
        counter[tag] = (counter[tag] ?? 0) + 1;
      }
    }
    final list = counter.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return list.take(limit).toList();
  }

  // ==================== 里程碑 ====================

  Future<List<MilestoneDef>> getMilestoneDefs() async {
    final db = await database;
    final rows = await db.query('milestone_def', orderBy: 'category ASC, sort_order ASC');
    return rows.map(MilestoneDef.fromMap).toList();
  }

  /// 里程碑 + 该宝宝达成情况
  Future<List<MilestoneStatus>> getMilestoneStatuses(int babyId) async {
    final db = await database;
    final defs = await getMilestoneDefs();
    final rows = await db.query(
      'growth_record',
      columns: ['milestone_code', 'record_time', 'uuid'],
      where: "baby_id = ? AND is_deleted = 0 AND record_type = 'milestone' AND milestone_code != ''",
      whereArgs: [babyId],
      orderBy: 'record_time ASC',
    );

    final achieved = <String, (DateTime, String)>{};
    for (final r in rows) {
      final code = r['milestone_code'] as String;
      // 取最早一次达成
      achieved.putIfAbsent(
        code,
        () => (DateTime.parse(r['record_time'] as String), r['uuid'] as String),
      );
    }

    return defs.map((d) {
      final hit = achieved[d.code];
      return MilestoneStatus(
        def: d,
        achievedAt: hit?.$1,
        recordUuid: hit?.$2,
      );
    }).toList();
  }

  Future<bool> isMilestoneAchieved(int babyId, String code) async {
    final db = await database;
    final n = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM growth_record WHERE baby_id = ? AND is_deleted = 0 AND milestone_code = ?",
          [babyId, code],
        )) ??
        0;
    return n > 0;
  }

  Future<MilestoneDef?> getMilestoneDef(String code) async {
    final db = await database;
    final r = await db.query('milestone_def', where: 'code = ?', whereArgs: [code], limit: 1);
    if (r.isEmpty) return null;
    return MilestoneDef.fromMap(r.first);
  }

  /// 自定义里程碑入库
  Future<void> insertCustomMilestone(MilestoneDef def) async {
    final db = await database;
    await db.insert('milestone_def', def.copyWithPreset(0).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ==================== 媒体 ====================

  Future<int> insertMedia(MediaItem m) async {
    final db = await database;
    return db.insert('media_item', m.toMap());
  }

  Future<List<MediaItem>> getMediaForRecord(String recordUuid, {bool onlySyncable = false}) async {
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

  /// 记录被编辑后，删除不再引用的媒体行，返回被移除的相对路径
  Future<List<String>> retainMedia(String recordUuid, List<int> keepIds) async {
    final db = await database;
    final rows = await db.query('media_item', where: 'record_uuid = ?', whereArgs: [recordUuid]);
    final removed = <String>[];
    for (final row in rows) {
      final id = row['id'] as int;
      if (!keepIds.contains(id)) {
        removed.add(row['local_relative_path'] as String);
        await db.delete('media_item', where: 'id = ?', whereArgs: [id]);
      }
    }
    return removed;
  }

  // ==================== 成长测量 ====================

  Future<void> upsertGrowthMetric(GrowthMetric m) async {
    final db = await database;
    await db.insert('growth_metric', m.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<GrowthMetric>> getMetrics(int babyId) async {
    final db = await database;
    final list = await db.query(
      'growth_metric',
      where: 'baby_id = ? AND is_deleted = 0',
      whereArgs: [babyId],
      orderBy: 'metric_time ASC',
    );
    return list.map(GrowthMetric.fromMap).toList();
  }

  /// 同步用：跨宝宝取全部测量
  Future<List<GrowthMetric>> getAllMetrics() async {
    final db = await database;
    final list = await db.query('growth_metric', orderBy: 'metric_time ASC');
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

  // ==================== 同步 ====================

  Future<List<GrowthRecord>> getRecordsChangedSince(int sinceTs) async {
    final db = await database;
    final list = await db.query('growth_record', where: 'last_modify_ts > ?', whereArgs: [sinceTs]);
    return list.map(GrowthRecord.fromMap).toList();
  }

  Future<List<GrowthMetric>> getMetricsChangedSince(int sinceTs) async {
    final db = await database;
    final list = await db.query('growth_metric', where: 'last_modify_ts > ?', whereArgs: [sinceTs]);
    return list.map(GrowthMetric.fromMap).toList();
  }

  Future<void> insertSyncLog(SyncLog log) async {
    final db = await database;
    await db.insert('sync_log', log.toMap());
  }

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

  /// 最近一次成功备份时间（毫秒），0 表示从未备份
  Future<int> getLastBackupTs() async {
    final v = await getSetting('last_backup_ts');
    return int.tryParse(v ?? '0') ?? 0;
  }

  Future<void> markBackedUp() =>
      setSetting('last_backup_ts', DateTime.now().millisecondsSinceEpoch.toString());
}

/// 便于在数据层直接改预置标记
extension MilestoneDefX on MilestoneDef {
  MilestoneDef copyWithPreset(int preset) => MilestoneDef(
        code: code,
        category: category,
        name: name,
        monthMin: monthMin,
        monthMax: monthMax,
        isPreset: preset,
        sortOrder: sortOrder,
      );
}

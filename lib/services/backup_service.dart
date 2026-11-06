import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import 'media_service.dart';

/// 本地备份：打包 SQLite 数据库 + compressed 媒体为 ZIP；支持从 ZIP 整库恢复。
/// 说明：origin（原图/原视频）不打进备份包，需单独手动拷贝到硬盘。
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const _dbName = 'little_footprint.db';
  static const _dbEntry = 'db/$_dbName';
  static const _mediaPrefix = 'media/compressed/';

  Future<String> exportBackupZip() async {
    final dbPath = p.join(await getDatabasesPath(), _dbName);

    final compressedDir = await MediaService.instance.compressedDir;
    final archive = Archive();

    // 数据库文件。
    // 先做一次 WAL checkpoint：否则 WAL 里还没合并进主文件的数据不会出现在备份里，
    // 导出的备份可能缺最近几条记录。
    final db = await AppDatabase.instance.database;
    await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    if (await File(dbPath).exists()) {
      final bytes = await File(dbPath).readAsBytes();
      archive.addFile(ArchiveFile(_dbEntry, bytes.length, bytes));
    }

    // compressed 媒体
    await for (final entity in compressedDir.list(recursive: true)) {
      if (entity is File) {
        final rel = p.relative(entity.path, from: compressedDir.path);
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile('$_mediaPrefix$rel', bytes.length, bytes));
      }
    }

    final encoder = ZipEncoder();
    final zipData = encoder.encode(archive)!;

    // 写到公共 Download 目录
    final downloadDir = Directory('/storage/emulated/0/Download');
    if (!await downloadDir.exists()) {
      downloadDir.createSync(recursive: true);
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    final fileName = '小脚印备份_$ts.zip';
    final target = File(p.join(downloadDir.path, fileName));
    await target.writeAsBytes(zipData);
    return target.path;
  }

  /// 从备份 ZIP 整库恢复（覆盖当前手机全部数据）。
  ///
  /// 顺序：先落媒体、再原子换库——换库是唯一不可逆的动作，放最后。
  /// 返回导入的媒体文件数。
  Future<int> importBackupZip(String zipPath) async {
    final zipBytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);

    ArchiveFile? dbEntry;
    for (final f in archive) {
      if (f.isFile && f.name == _dbEntry) {
        dbEntry = f;
        break;
      }
    }
    if (dbEntry == null) {
      throw const FormatException('不是有效的备份包：缺少数据库文件');
    }
    final dbBytes = Uint8List.fromList((dbEntry.content as List).cast<int>());
    _validateSqlite(dbBytes);

    // 1) 恢复媒体。zip-slip 防护：归一化后必须仍在媒体目录内。
    final compressedDir = await MediaService.instance.compressedDir;
    var mediaCount = 0;
    for (final f in archive) {
      if (!f.isFile || !f.name.startsWith(_mediaPrefix)) continue;
      final rel = f.name.substring(_mediaPrefix.length);
      if (rel.isEmpty || rel.startsWith('/')) continue;
      final target = p.normalize(p.join(compressedDir.path, rel));
      if (!p.isWithin(compressedDir.path, target)) continue;
      final out = File(target);
      await out.create(recursive: true);
      await out
          .writeAsBytes(Uint8List.fromList((f.content as List).cast<int>()));
      mediaCount++;
    }

    // 2) 换库。先关连接（顺带把 WAL 合并回主文件），
    //    再删掉旧的 -wal/-shm 残留——留着它们会用旧数据污染新库。
    await AppDatabase.instance.closeForRestore();
    final dbPath = await AppDatabase.instance.databaseFilePath();
    final tmp = File('$dbPath.restoring');
    await tmp.writeAsBytes(dbBytes);
    for (final suffix in const ['-wal', '-shm']) {
      final f = File('$dbPath$suffix');
      if (await f.exists()) await f.delete();
    }
    // 同分区 rename，原子生效；写到一半失败也不会损坏原库
    await tmp.rename(dbPath);

    // 3) 重新打开。备份的 schema 版本较旧时，这里会自动跑迁移。
    await AppDatabase.instance.database;
    return mediaCount;
  }

  /// 校验是 SQLite 文件且 schema 版本不高于本机。
  /// sqflite 的默认降级策略是删库重建——比这更糟的方案想不出来，
  /// 所以必须在打开前就把「新备份灌进旧 app」挡掉。
  void _validateSqlite(Uint8List bytes) {
    const magic = 'SQLite format 3';
    if (bytes.length < 100 ||
        String.fromCharCodes(bytes.sublist(0, magic.length)) != magic) {
      throw const FormatException('备份里的数据库文件已损坏');
    }
    final userVersion =
        (bytes[60] << 24) | (bytes[61] << 16) | (bytes[62] << 8) | bytes[63];
    if (userVersion > AppDatabase.schemaVersion) {
      throw FormatException('备份来自更高版本的应用（schema v$userVersion），请先升级 app 再恢复');
    }
  }
}

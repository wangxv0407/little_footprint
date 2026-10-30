import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'media_service.dart';

/// 本地备份导出：打包 SQLite 数据库 + compressed 媒体为 ZIP。
/// 说明：origin（原图/原视频）不打进备份包，需单独手动拷贝到硬盘。
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  Future<String> exportBackupZip() async {
    final dbPath = p.join(await getDatabasesPath(), 'little_footprint.db');

    final compressedDir = await MediaService.instance.compressedDir;
    final archive = Archive();

    // 数据库文件
    if (await File(dbPath).exists()) {
      final bytes = await File(dbPath).readAsBytes();
      archive.addFile(ArchiveFile('db/little_footprint.db', bytes.length, bytes));
    }

    // compressed 媒体
    await for (final entity in compressedDir.list(recursive: true)) {
      if (entity is File) {
        final rel = p.relative(entity.path, from: compressedDir.path);
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile('media/compressed/$rel', bytes.length, bytes));
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
}

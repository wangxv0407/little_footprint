import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 媒体文件管理：目录规划、压缩预览、MD5 计算、保存到相册
class MediaService {
  MediaService._();
  static final MediaService instance = MediaService._();

  static const int previewMaxEdge = 1200; // 压缩预览图长边像素

  /// 返回媒体根目录：<docs>/records
  Future<Directory> get recordsRoot async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'records'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// compressed 目录：压缩图 / 压缩视频 / AAC录音（参与同步）
  Future<Directory> get compressedDir async =>
      _ensure(await recordsRoot, 'compressed');

  /// origin 目录：原图 / 原视频（仅本机，不同步）
  Future<Directory> get originDir async => _ensure(await recordsRoot, 'origin');

  Future<Directory> _ensure(Directory parent, String name) async {
    final dir = Directory(p.join(parent.path, name));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 头像目录：<docs>/avatars
  Future<Directory> get avatarDir async {
    final docs = await getApplicationDocumentsDirectory();
    return _ensure(docs, 'avatars');
  }

  /// 保存宝宝头像到应用私有目录，返回绝对路径。
  /// [oldPath] 非空时删除旧头像文件，避免越积越多。
  Future<String> storeAvatar(String srcPath, {String? oldPath}) async {
    final dir = await avatarDir;
    final ext = p.extension(srcPath).isEmpty ? '.jpg' : p.extension(srcPath);
    final fileName = 'baby_${DateTime.now().millisecondsSinceEpoch}_${_randSuffix()}$ext';
    final target = File(p.join(dir.path, fileName));
    await target.writeAsBytes(await File(srcPath).readAsBytes());

    if (oldPath != null && oldPath.isNotEmpty && oldPath != target.path) {
      try {
        final old = File(oldPath);
        if (await old.exists()) await old.delete();
      } catch (_) {
        // 旧文件删不掉不影响功能
      }
    }
    return target.path;
  }

  /// 压缩图片：生成长边 1200px 的 JPEG 预览图，写入 compressed 目录，返回 (MediaItem 相关参数, 绝对路径)
  Future<(String absolutePath, String relativePath, String md5, int size)>
      createCompressedImage(String srcPath) async {
    final bytes = await File(srcPath).readAsBytes();
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('无法解码图片: $srcPath');
    }
    // 等比缩放
    img.Image resized = decoded;
    if (decoded.width > previewMaxEdge || decoded.height > previewMaxEdge) {
      if (decoded.width >= decoded.height) {
        resized =
            img.copyResize(decoded, width: previewMaxEdge, interpolation: img.Interpolation.linear);
      } else {
        resized =
            img.copyResize(decoded, height: previewMaxEdge, interpolation: img.Interpolation.linear);
      }
    }
    final outBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 85));

    final dir = await compressedDir;
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${_randSuffix()}.jpg';
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(outBytes);

    return (
      file.path,
      p.relative(file.path, from: (await recordsRoot).path),
      await md5Of(file.path),
      outBytes.length,
    );
  }

  /// 把源文件（原图/原视频）复制到 origin 目录，返回相对路径
  Future<(String absolutePath, String relativePath, String md5, int size)>
      storeOrigin(String srcPath) async {
    final dir = await originDir;
    final ext = p.extension(srcPath);
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${_randSuffix()}$ext';
    final target = File(p.join(dir.path, fileName));
    await target.writeAsBytes(await File(srcPath).readAsBytes());
    return (
      target.path,
      p.relative(target.path, from: (await recordsRoot).path),
      await md5Of(target.path),
      await target.length(),
    );
  }

  /// 复制已存在的录音到 compressed 目录（用于入库）
  Future<(String absolutePath, String relativePath, String md5, int size)>
      storeRecording(String srcPath) async {
    final dir = await compressedDir;
    final ext = p.extension(srcPath).isEmpty ? '.aac' : p.extension(srcPath);
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${_randSuffix()}$ext';
    final target = File(p.join(dir.path, fileName));
    await target.writeAsBytes(await File(srcPath).readAsBytes());
    return (
      target.path,
      p.relative(target.path, from: (await recordsRoot).path),
      await md5Of(target.path),
      await target.length(),
    );
  }

  /// 计算文件 MD5
  Future<String> md5Of(String filePath) async {
    final data = await File(filePath).readAsBytes();
    return md5.convert(data).toString();
  }

  /// 根据相对路径拼接绝对路径
  Future<String> absolutePathOf(String relativePath) async {
    return p.join((await recordsRoot).path, relativePath);
  }

  /// 保存图片到系统相册。
  ///
  /// Android 10+ 通过 MediaStore 写入「Pictures/小脚印」，不需要任何存储权限；
  /// Android 9 及以下回退到公共目录（Manifest 已声明 maxSdkVersion=29 的写权限）。
  /// 旧实现直接写 `/storage/emulated/0/Pictures`，在分区存储下必然失败。
  Future<String> saveToGallery(String srcPath) async {
    if (!await Gal.hasAccess(toAlbum: true)) {
      final granted = await Gal.requestAccess(toAlbum: true);
      if (!granted) {
        throw Exception('没有相册写入权限，请在系统设置中开启');
      }
    }
    await Gal.putImage(srcPath, album: '小脚印');
    return p.basename(srcPath);
  }

  String _randSuffix() {
    return (DateTime.now().microsecondsSinceEpoch % 0xFFFFFF).toRadixString(16);
  }
}

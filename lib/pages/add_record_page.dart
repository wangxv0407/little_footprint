import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../models/growth_record.dart';
import '../models/media_item.dart';
import '../services/media_service.dart';
import '../theme.dart';
import '../widgets/tag_wrap.dart';

class AddRecordPage extends StatefulWidget {
  const AddRecordPage({super.key});

  @override
  State<AddRecordPage> createState() => _AddRecordPageState();
}

class _AddRecordPageState extends State<AddRecordPage> {
  final _contentCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final _tags = <String>[];
  DateTime _recordTime = DateTime.now();

  final _picker = ImagePicker();
  final _recorder = AudioRecorder();
  bool _recording = false;
  String? _recordedPath;

  List<String> _pickedImagePaths = [];
  String? _pickedVideoPath;

  static const _presetTags = ['翻身', '辅食', '疫苗', '出游', '学说话'];

  @override
  void dispose() {
    _contentCtrl.dispose();
    _tagCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _recordTime,
      firstDate: DateTime(DateTime.now().year - 3),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      final t = TimeOfDay.fromDateTime(_recordTime);
      setState(() {
        _recordTime = DateTime(picked.year, picked.month, picked.day, t.hour, t.minute);
      });
    }
  }

  Future<void> _pickImages() async {
    final perms = await Permission.photos.request();
    if (!perms.isGranted) {
      _snack('需要相册权限');
      return;
    }
    final files = await _picker.pickMultiImage(source: ImageSource.gallery);
    if (files != null && files.isNotEmpty) {
      setState(() {
        _pickedImagePaths.addAll(files.map((f) => f.path).toList());
      });
    }
  }

  Future<void> _pickVideo() async {
    final perms = await Permission.photos.request();
    if (!perms.isGranted) {
      _snack('需要相册权限');
      return;
    }
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file != null) {
      setState(() => _pickedVideoPath = file.path);
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      setState(() {
        _recording = false;
        _recordedPath = path;
      });
      _snack('录音完成');
    } else {
      final granted = await Permission.microphone.request();
      if (!granted.isGranted) {
        _snack('需要麦克风权限');
        return;
      }
      final dir = await MediaService.instance.compressedDir;
      final path = p.join(dir.path, 'rec_${DateTime.now().millisecondsSinceEpoch}.aac');
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      setState(() => _recording = true);
    }
  }

  void _addTag([String? value]) {
    final v = (value ?? _tagCtrl.text).trim();
    if (v.isEmpty) return;
    if (_tags.contains(v)) {
      _tagCtrl.clear();
      return;
    }
    setState(() {
      _tags.add(v);
      _tagCtrl.clear();
    });
  }

  Future<void> _save() async {
    final db = AppDatabase.instance;
    final media = MediaService.instance;
    final uuid = const Uuid().v4();
    final ts = DateTime.now().millisecondsSinceEpoch;

    final record = GrowthRecord(
      uuid: uuid,
      recordTime: _recordTime,
      content: _contentCtrl.text.trim(),
      tags: List.of(_tags),
      createDevice: (await db.getBabyInfo())?.deviceRole ?? 'husband',
      lastModifyTs: ts,
      isDeleted: 0,
    );
    await db.upsertGrowthRecord(record);

    // 照片：生成压缩预览图（参与同步），原图保留在用户相册
    for (final path in _pickedImagePaths) {
      try {
        final r = await media.createCompressedImage(path);
        await db.insertMedia(MediaItem(
          id: 0,
          recordUuid: uuid,
          fileName: p.basename(r.$1),
          fileType: 'image',
          localRelativePath: r.$2,
          fileMd5: r.$3,
          fileSize: r.$4,
          isOrigin: 0,
        ));
      } catch (e) {
        _snack('图片处理失败: $e');
      }
    }

    // 录音：复制到 compressed（参与同步）
    if (_recordedPath != null && await File(_recordedPath!).exists()) {
      final r = await media.storeRecording(_recordedPath!);
      await db.insertMedia(MediaItem(
        id: 0,
        recordUuid: uuid,
        fileName: p.basename(r.$1),
        fileType: 'audio',
        localRelativePath: r.$2,
        fileMd5: r.$3,
        fileSize: r.$4,
        isOrigin: 0,
      ));
    }

    // 视频：MVP 仅本机保存原视频（is_origin=1，不参与跨机同步）
    if (_pickedVideoPath != null && await File(_pickedVideoPath!).exists()) {
      final r = await media.storeOrigin(_pickedVideoPath!);
      await db.insertMedia(MediaItem(
        id: 0,
        recordUuid: uuid,
        fileName: p.basename(r.$1),
        fileType: 'video',
        localRelativePath: r.$2,
        fileMd5: r.$3,
        fileSize: r.$4,
        isOrigin: 1,
      ));
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新增记录')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 发生时间
            _sectionLabel('发生时间'),
            InkWell(
              onTap: _pickTime,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, color: AppColors.primary, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      DateFormat('yyyy-MM-dd HH:mm').format(_recordTime),
                      style: const TextStyle(fontSize: 15, color: AppColors.textMain),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 文字日记
            _sectionLabel('文字日记'),
            TextField(
              controller: _contentCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '写下此刻的小事…',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 标签
            _sectionLabel('标签'),
            TextField(
              controller: _tagCtrl,
              onSubmitted: _addTag,
              decoration: const InputDecoration(
                hintText: '输入标签后回车添加',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              TagWrap(tags: _tags, onDelete: (t) => setState(() => _tags.remove(t))),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: _presetTags
                  .where((t) => !_tags.contains(t))
                  .map((t) => ActionChip(
                        label: Text(t, style: const TextStyle(fontSize: 12)),
                        onPressed: () => _addTag(t),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            // 媒体
            _sectionLabel('媒体'),
            const SizedBox(height: 10),
            // 照片
            _photoSection(),
            const SizedBox(height: 10),
            // 录音
            _audioSection(),
            const SizedBox(height: 10),
            // 视频
            _videoSection(),
            const SizedBox(height: 30),
            FilledButton(onPressed: _save, child: const Text('保存')),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, color: AppColors.secondaryText, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _photoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final path in _pickedImagePaths)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(path), width: 80, height: 80, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: GestureDetector(
                      onTap: () => setState(() => _pickedImagePaths.remove(path)),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            GestureDetector(
              onTap: _pickImages,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_a_photo, color: AppColors.primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text('压缩预览图参与同步，原图保留在手机相册',
            style: TextStyle(fontSize: 11, color: Color(0xFFB0B0B0))),
      ],
    );
  }

  Widget _audioSection() {
    return GestureDetector(
      onTap: _toggleRecording,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: _recording ? Colors.red.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _recording ? Colors.redAccent : AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(
              _recording ? Icons.stop_circle_outlined : Icons.mic,
              color: _recording ? Colors.redAccent : AppColors.primary,
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _recording
                    ? '正在录音…点击停止'
                    : (_recordedPath != null ? '已录音 · 点击重新录制' : '点击开始录音（AAC）'),
                style: TextStyle(
                  fontSize: 14,
                  color: _recording ? Colors.redAccent : AppColors.textMain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _videoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _pickVideo,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                const Icon(Icons.videocam, color: AppColors.primary, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _pickedVideoPath == null ? '选择视频（MP4）' : '已选择视频 · 点击更换',
                    style: const TextStyle(fontSize: 14, color: AppColors.textMain),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text('MVP 视频仅保存在本机，不跨机同步；请自行硬盘备份',
            style: TextStyle(fontSize: 11, color: Color(0xFFB0B0B0))),
      ],
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../db/app_database.dart';
import '../models/growth_record.dart';
import '../models/media_item.dart';
import '../services/media_service.dart';
import '../theme.dart';
import '../utils/age_calculator.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/tag_wrap.dart';
import 'media_viewer_page.dart';

class RecordDetailPage extends StatefulWidget {
  final String recordUuid;
  const RecordDetailPage({super.key, required this.recordUuid});

  @override
  State<RecordDetailPage> createState() => _RecordDetailPageState();
}

class _RecordDetailPageState extends State<RecordDetailPage> {
  GrowthRecord? _record;
  List<MediaItem> _medias = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDatabase.instance;
    final record = await db.getGrowthRecord(widget.recordUuid);
    final medias = await db.getMediaForRecord(widget.recordUuid);
    if (!mounted) return;
    setState(() {
      _record = record;
      _medias = medias;
      _loading = false;
    });
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: const Text('记录将被标记删除，同步时会同步删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AppDatabase.instance.deleteRecordSoft(widget.recordUuid);
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _record == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final r = _record!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('记录详情'),
        actions: [
          IconButton(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder(
        future: AppDatabase.instance.getBabyInfo(),
        builder: (context, snap) {
          final birth = snap.data?.birthDate ?? DateTime.now();
          final ageText = AgeCalculator.fullText(birth, r.recordTime);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${DateFormat('yyyy-MM-dd HH:mm').format(r.recordTime)} · $ageText',
                style: const TextStyle(fontSize: 13, color: AppColors.secondaryText),
              ),
              const SizedBox(height: 4),
              Text(
                '记录人：${r.createDevice == 'wife' ? '妈妈' : '爸爸'}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFB0B0B0)),
              ),
              const SizedBox(height: 14),
              if (r.content.isNotEmpty)
                Text(
                  r.content,
                  style: const TextStyle(
                      fontSize: 16, color: AppColors.textMain, height: 1.6),
                ),
              if (r.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                TagWrap(tags: r.tags),
              ],
              const SizedBox(height: 16),
              // 媒体
              for (final m in _medias) _mediaBlock(m, birth),
            ],
          );
        },
      ),
    );
  }

  Widget _mediaBlock(MediaItem m, DateTime birth) {
    if (m.fileType == 'image') {
      return FutureBuilder<String>(
        future: MediaService.instance.absolutePathOf(m.localRelativePath),
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MediaViewerPage(
                  initialIndex: _medias.indexOf(m),
                  imagePaths: _medias
                      .where((x) => x.fileType == 'image')
                      .map((x) => x.localRelativePath)
                      .toList(),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(snap.data!),
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      );
    }
    if (m.fileType == 'audio') {
      return FutureBuilder<String>(
        future: MediaService.instance.absolutePathOf(m.localRelativePath),
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AudioPlayerWidget(filePath: snap.data!),
          );
        },
      );
    }
    if (m.fileType == 'video') {
      return FutureBuilder<String>(
        future: MediaService.instance.absolutePathOf(m.localRelativePath),
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _VideoPlayer(filePath: snap.data!),
          );
        },
      );
    }
    return const SizedBox.shrink();
  }
}

class _VideoPlayer extends StatefulWidget {
  final String filePath;
  const _VideoPlayer({required this.filePath});

  @override
  State<_VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<_VideoPlayer> {
  late VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath));
    _controller.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    });
    _controller.setLooping(false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFF2F2F2F),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
      );
    }
    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            VideoPlayer(_controller),
            _controls(),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    return GestureDetector(
      onTap: () {
        if (_controller.value.isPlaying) {
          _controller.pause();
        } else {
          _controller.play();
        }
        setState(() {});
      },
      child: Container(
        color: Colors.black26,
        child: Center(
          child: Icon(
            _controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
            color: Colors.white,
            size: 56,
          ),
        ),
      ),
    );
  }
}

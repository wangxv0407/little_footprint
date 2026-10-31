import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../db/app_database.dart';
import '../models/baby_info.dart';
import '../models/growth_record.dart';
import '../models/media_item.dart';
import '../services/media_service.dart';
import '../theme.dart';
import '../utils/age_calculator.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/common.dart';
import 'add_record_page.dart';
import 'media_viewer_page.dart';

/// 记录详情
class RecordDetailPage extends StatefulWidget {
  final String recordUuid;

  const RecordDetailPage({super.key, required this.recordUuid});

  @override
  State<RecordDetailPage> createState() => _RecordDetailPageState();
}

class _RecordDetailPageState extends State<RecordDetailPage> {
  GrowthRecord? _record;
  BabyInfo? _baby;
  List<MediaItem> _medias = const [];
  String _msName = '';
  String _rootPath = '';
  bool _loading = true;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDatabase.instance;
    _rootPath = (await MediaService.instance.recordsRoot).path;
    final r = await db.getGrowthRecord(widget.recordUuid);
    if (r == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    final baby = await db.getBabyById(r.babyId);
    final medias = await db.getMediaForRecord(r.uuid);
    var msName = '';
    if (r.milestoneCode.isNotEmpty) {
      msName = (await db.getMilestoneDef(r.milestoneCode))?.name ?? '';
    }
    if (!mounted) return;
    setState(() {
      _record = r;
      _baby = baby;
      _medias = medias;
      _msName = msName;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.paper,
        body: Center(child: CircularProgressIndicator(color: AppColors.clay)),
      );
    }
    final r = _record;
    if (r == null || r.isDeleted == 1) {
      return Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(backgroundColor: AppColors.paper, title: const Text('记录详情')),
        body: const EmptyState(icon: Icons.inbox_outlined, title: '这条记录已被删除'),
      );
    }

    final images = _medias.where((m) => m.fileType == 'image').toList();
    final audios = _medias.where((m) => m.fileType == 'audio').toList();
    final videos = _medias.where((m) => m.fileType == 'video').toList();
    final birth = _baby?.birthDate ?? DateTime.now();

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.ink2),
          onPressed: () => Navigator.pop(context, _changed),
        ),
        title: const Text('记录详情',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: AppColors.ink2),
            color: AppColors.paper,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            onSelected: _onMenu,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑')),
              PopupMenuItem(
                value: 'fav',
                child: Text(r.isFavoriteRecord ? '取消收藏' : '收藏'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('删除', style: TextStyle(color: Color(0xFFB3261E))),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.pageX, 4, AppSpace.pageX, 24),
        children: [
          if (r.isMilestone) ...[
            AppBadge.pine(
              _msName.isEmpty ? '里程碑' : _msName,
              icon: Icons.workspace_premium,
            ),
            const SizedBox(height: AppSpace.md),
          ],
          Text(
            DateFormat('yyyy 年 M 月 d 日 · HH:mm').format(r.recordTime),
            style: TextStyle(
              fontFamily: AppFonts.serif,
              fontFamilyFallback: AppFonts.serifFallback,
              fontSize: 14,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${AgeCalculator.fullText(birth, r.recordTime)} · 记录人 ${r.authorLabel}',
            style: AppText.caption,
          ),
          if (r.content.isNotEmpty) ...[
            const SizedBox(height: AppSpace.lg),
            Text(
              r.content,
              style: const TextStyle(fontSize: 14.5, height: 1.95, color: AppColors.ink),
            ),
          ],
          if (r.tags.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in r.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.clayLight,
                      borderRadius: AppRadius.pill,
                    ),
                    child: Text(t,
                        style: const TextStyle(fontSize: 11.5, color: AppColors.clayDark)),
                  ),
              ],
            ),
          ],
          if (images.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            for (var i = 0; i < images.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => _openImage(images, i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Image.file(
                      File(p.join(_rootPath, images[i].localRelativePath)),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 120,
                        color: AppColors.line,
                        alignment: Alignment.center,
                        child: Text('文件已丢失', style: AppText.caption),
                      ),
                    ),
                  ),
                ),
              ),
          ],
          for (final a in audios) ...[
            const SizedBox(height: AppSpace.xs),
            AppCard(
              padding: const EdgeInsets.all(12),
              child: AudioPlayerWidget(
                filePath: p.join(_rootPath, a.localRelativePath),
              ),
            ),
          ],
          for (final v in videos) ...[
            const SizedBox(height: AppSpace.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: _VideoBlock(filePath: p.join(_rootPath, v.localRelativePath)),
            ),
            if (v.isOrigin == 1)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('此视频仅保存在本机，未参与双机同步', style: AppText.caption),
              ),
          ],
          const SizedBox(height: AppSpace.xl),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _toggleFavorite,
                  icon: Icon(
                    r.isFavoriteRecord ? Icons.star : Icons.star_border,
                    size: 18,
                    color: r.isFavoriteRecord ? AppColors.gold : AppColors.ink2,
                  ),
                  label: Text(r.isFavoriteRecord ? '已收藏' : '收藏'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _openEdit,
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: const Text('编辑'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onMenu(String value) async {
    switch (value) {
      case 'edit':
        await _openEdit();
      case 'fav':
        await _toggleFavorite();
      case 'delete':
        await _delete();
    }
  }

  Future<void> _openEdit() async {
    final r = _record!;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddRecordPage(
          babyId: r.babyId,
          recordUuid: r.uuid,
        ),
      ),
    );
    if (ok == true) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _toggleFavorite() async {
    final r = _record!;
    await AppDatabase.instance.toggleFavorite(r.uuid, !r.isFavoriteRecord);
    _changed = true;
    await _load();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: const Text('删除这条记录？', style: TextStyle(fontSize: 16)),
        content: const Text(
          '删除会同步到另一台手机。媒体文件会在「清理缓存」时释放空间。',
          style: TextStyle(fontSize: 13, height: 1.7),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFB3261E)),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AppDatabase.instance.deleteRecordSoft(widget.recordUuid);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  void _openImage(List<MediaItem> images, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaViewerPage(
          initialIndex: index,
          imagePaths: images.map((e) => e.localRelativePath).toList(),
        ),
      ),
    );
  }
}

class _VideoBlock extends StatefulWidget {
  final String filePath;
  const _VideoBlock({required this.filePath});

  @override
  State<_VideoBlock> createState() => _VideoBlockState();
}

class _VideoBlockState extends State<_VideoBlock> {
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
        color: const Color(0xFF2F2F2F),
        alignment: Alignment.center,
        child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
      );
    }
    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio,
      child: Stack(
        alignment: Alignment.center,
        children: [
          VideoPlayer(_controller),
          GestureDetector(
            onTap: () {
              setState(() {
                _controller.value.isPlaying ? _controller.pause() : _controller.play();
              });
            },
            child: Container(
              color: Colors.black26,
              alignment: Alignment.center,
              child: Icon(
                _controller.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
                color: Colors.white,
                size: 52,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

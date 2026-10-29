import 'dart:io';

import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../services/media_service.dart';

/// 媒体预览组件：根据类型渲染 图片 / 录音 / 视频 缩略。
class MediaPreview extends StatelessWidget {
  final MediaItem media;
  final VoidCallback? onTap;
  final double? height;

  const MediaPreview({
    super.key,
    required this.media,
    this.onTap,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    switch (media.fileType) {
      case 'image':
        return _image(context);
      case 'audio':
        return _audio(context);
      case 'video':
        return _video(context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _image(BuildContext context) {
    return FutureBuilder<String>(
      future: MediaService.instance.absolutePathOf(media.localRelativePath),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(
            height: height ?? 160,
            color: const Color(0xFFEFEFEF),
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(snap.data!),
              height: height,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }

  Widget _audio(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height ?? 56,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF4A7C77).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(Icons.mic, color: const Color(0xFF4A7C77)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_formatSize(media.fileSize)} · 点击播放',
                style: const TextStyle(fontSize: 13, color: Color(0xFF4A7C77)),
              ),
            ),
            const Icon(Icons.play_circle_fill, color: Color(0xFF4A7C77), size: 28),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  Widget _video(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height ?? 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF2F2F2F),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.videocam_outlined,
                color: Colors.white.withValues(alpha: 0.85), size: 44),
            const Positioned(
              bottom: 8,
              child: Text('视频 · 点击播放',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '录音';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/growth_record.dart';
import '../models/media_item.dart';
import '../utils/age_calculator.dart';
import 'media_preview.dart';
import 'tag_wrap.dart';

/// 时间线卡片：时间 + 月龄 + 媒体预览 + 文字 + 标签 + 记录人
class TimelineCard extends StatelessWidget {
  final GrowthRecord record;
  final List<MediaItem> medias;
  final DateTime birthDate;
  final VoidCallback onTap;

  const TimelineCard({
    super.key,
    required this.record,
    required this.medias,
    required this.birthDate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(record.recordTime);
    final ageText = AgeCalculator.fullText(birthDate, record.recordTime);
    final images = medias.where((m) => m.fileType == 'image').toList();
    final audios = medias.where((m) => m.fileType == 'audio').toList();
    final videos = medias.where((m) => m.fileType == 'video').toList();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$dateStr · $ageText',
              style: const TextStyle(fontSize: 12, color: Color(0xFF707070)),
            ),
            const SizedBox(height: 10),
            // 媒体区
            if (images.isNotEmpty)
              _mediaBlock(images, context)
            else if (videos.isNotEmpty)
              MediaPreview(media: videos.first, onTap: onTap)
            else if (audios.isNotEmpty)
              MediaPreview(media: audios.first, onTap: onTap),
            if (record.content.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                record.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF333333), height: 1.5),
              ),
            ],
            if (record.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              TagWrap(tags: record.tags),
            ],
            const SizedBox(height: 8),
            Text(
              '记录人：${record.createDevice == 'wife' ? '妈妈' : '爸爸'}',
              style: const TextStyle(fontSize: 11, color: Color(0xFFB0B0B0)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaBlock(List<MediaItem> images, BuildContext context) {
    if (images.length == 1) {
      return MediaPreview(media: images.first, onTap: onTap);
    }
    // 多张横向滚动
    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          return SizedBox(
            width: 200,
            child: MediaPreview(media: images[i], onTap: onTap),
          );
        },
      ),
    );
  }
}

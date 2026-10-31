import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../db/app_database.dart';
import '../models/baby_info.dart';
import '../models/growth_record.dart';
import '../models/media_item.dart';
import '../services/media_service.dart';
import '../theme.dart';
import '../utils/age_calculator.dart';
import '../widgets/common.dart';
import 'add_record_page.dart';
import 'baby_info_page.dart';
import 'record_detail_page.dart';
import 'search_page.dart';

/// 时间轴首页
class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});

  @override
  State<TimelinePage> createState() => TimelinePageState();
}

class TimelinePageState extends State<TimelinePage> {
  BabyInfo? _baby;
  List<GrowthRecord> _records = const [];
  Map<String, List<MediaItem>> _mediaMap = const {};
  Map<String, String> _msNames = const {};
  List<GrowthRecord> _lastYear = const [];
  String _rootPath = '';
  RecordFilter _filter = RecordFilter.all;
  bool _loading = true;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final db = AppDatabase.instance;
    final baby = await db.getActiveBaby();
    final root = (await MediaService.instance.recordsRoot).path;

    if (baby == null) {
      if (!mounted) return;
      setState(() {
        _baby = null;
        _records = const [];
        _mediaMap = const {};
        _rootPath = root;
        _loading = false;
      });
      return;
    }

    final records = await db.getRecords(baby.id, filter: _filter);
    final mediaMap = await db.getMediaMapForBaby(baby.id);
    final defs = await db.getMilestoneDefs();
    final msNames = {for (final d in defs) d.code: d.name};

    // 「去年今天」：仅在有内容时展示
    final now = DateTime.now();
    final sameDayLastYear = DateTime(now.year - 1, now.month, now.day);
    final lastYear = await db.searchRecords(
      baby.id,
      '',
      from: sameDayLastYear,
      to: sameDayLastYear.add(const Duration(days: 1)),
    );

    if (!mounted) return;
    setState(() {
      _baby = baby;
      _records = records;
      _mediaMap = mediaMap;
      _msNames = msNames;
      _rootPath = root;
      _lastYear = lastYear;
      _loading = false;
    });
  }

  void _setFilter(RecordFilter f) {
    if (_filter == f) return;
    setState(() => _filter = f);
    load();
  }

  // ==================== 分组 ====================

  /// 按自然日分组，标题用相对日期
  List<_DaySection> _sections() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sections = <_DaySection>[];
    for (final r in _records) {
      final d = DateTime(r.recordTime.year, r.recordTime.month, r.recordTime.day);
      if (sections.isNotEmpty && sections.last.day == d) {
        sections.last.items.add(r);
      } else {
        sections.add(_DaySection(d, _dayTitle(d, today), [r]));
      }
    }
    return sections;
  }

  String _dayTitle(DateTime d, DateTime today) {
    final diff = today.difference(d).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff == 2) return '前天';
    final w = _weekdays[d.weekday - 1];
    if (d.year == today.year) {
      return '${d.month}月${d.day}日 周$w';
    }
    return '${d.year}年${d.month}月${d.day}日 周$w';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.clay))
            : _baby == null
                ? _noBaby()
                : _content(),
      ),
      floatingActionButton: _baby == null
          ? null
          : FloatingActionButton(
              onPressed: _openAdd,
              child: const Icon(Icons.add, size: 28),
            ),
    );
  }

  Widget _content() {
    final sections = _sections();
    return RefreshIndicator(
      color: AppColors.clay,
      onRefresh: load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header()),
          if (_lastYear.isNotEmpty) SliverToBoxAdapter(child: _lastYearCard()),
          SliverToBoxAdapter(child: _filterBar()),
          if (sections.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.photo_library_outlined,
                title: _filter == RecordFilter.all ? '还没有成长记录' : '这个筛选下暂时没有记录',
                subtitle: _filter == RecordFilter.all ? '点击右下角 + ，记下宝宝第一个瞬间' : null,
              ),
            )
          else
            SliverList.builder(
              itemCount: sections.length,
              itemBuilder: (context, i) {
                final s = sections[i];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _dayHeader(s.title),
                    for (var j = 0; j < s.items.length; j++)
                      _entry(
                        s.items[j],
                        isLast: i == sections.length - 1 && j == s.items.length - 1,
                      ),
                  ],
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ],
      ),
    );
  }

  Widget _noBaby() {
    return EmptyState(
      icon: Icons.child_care,
      title: '还没有建档',
      subtitle: '先添加宝宝信息，才能开始记录',
      action: FilledButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BabyInfoPage()),
          );
          load();
        },
        child: const Text('添加宝宝'),
      ),
    );
  }

  // ==================== 顶部 ====================

  Widget _header() {
    final baby = _baby!;
    final now = DateTime.now();
    final age = AgeCalculator.titleText(baby.birthDate, now);
    final dateText =
        '${now.year} 年 ${now.month} 月 ${now.day} 日 · 周${_weekdays[now.weekday - 1]}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.pageX, 8, AppSpace.sm, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _switchBaby,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dateText, style: AppText.caption.copyWith(letterSpacing: 1.2)),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(baby.babyName.isEmpty ? '宝宝' : baby.babyName,
                          style: AppText.serifTitle()),
                      const SizedBox(width: 6),
                      Text(age,
                          style: const TextStyle(fontSize: 12, color: AppColors.ink2)),
                      const SizedBox(width: 2),
                      const Icon(Icons.keyboard_arrow_down,
                          size: 18, color: AppColors.ink3),
                    ],
                  ),
                ],
              ),
            ),
          ),
          AppIconButton(
            icon: Icons.search,
            tooltip: '搜索',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SearchPage(babyId: _baby!.id)),
              );
              load();
            },
          ),
        ],
      ),
    );
  }

  Widget _lastYearCard() {
    final first = _lastYear.first;
    final medias = _mediaMap[first.uuid] ?? const <MediaItem>[];
    final images = medias.where((m) => m.fileType == 'image').toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.pageX, 0, AppSpace.pageX, 14),
      child: AppCard(
        padding: const EdgeInsets.all(11),
        onTap: () => _openDetail(first),
        child: Row(
          children: [
            _Thumb(
              media: images.isEmpty ? null : images.first,
              rootPath: _rootPath,
              size: 44,
              radius: 10,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('去年的今天',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.clay,
                        letterSpacing: 1.2,
                      )),
                  const SizedBox(height: 3),
                  Text(
                    first.content.isEmpty ? '这一天有 ${_lastYear.length} 条记录' : first.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }

  Widget _filterBar() {
    const items = <(RecordFilter, String)>[
      (RecordFilter.all, '全部'),
      (RecordFilter.photo, '照片'),
      (RecordFilter.audio, '录音'),
      (RecordFilter.video, '视频'),
      (RecordFilter.milestone, '里程碑'),
      (RecordFilter.favorite, '收藏'),
    ];
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageX),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (f, label) = items[i];
          return Center(
            child: AppChip(
              label: label,
              selected: _filter == f,
              onTap: () => _setFilter(f),
            ),
          );
        },
      ),
    );
  }

  Widget _dayHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.pageX, 10, AppSpace.pageX, 10),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: AppFonts.serif,
              fontFamilyFallback: AppFonts.serifFallback,
              fontSize: 13,
              color: AppColors.ink2,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Divider(height: 1, color: AppColors.line)),
        ],
      ),
    );
  }

  // ==================== 条目 ====================

  Widget _entry(GrowthRecord r, {bool isLast = false}) {
    final medias = _mediaMap[r.uuid] ?? const <MediaItem>[];
    return Padding(
      padding: const EdgeInsets.only(left: AppSpace.pageX),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 16,
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: r.isMilestone ? AppColors.pine : AppColors.lineStrong,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.paper, width: 1.4),
                    ),
                  ),
                  if (!isLast)
                    Expanded(child: Container(width: 1, color: AppColors.line)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 8, right: AppSpace.pageX, bottom: 12),
                child: _recordCard(r, medias),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recordCard(GrowthRecord r, List<MediaItem> medias) {
    final images = medias.where((m) => m.fileType == 'image').toList();
    final hasAudio = medias.any((m) => m.fileType == 'audio');
    final hasVideo = medias.any((m) => m.fileType == 'video');

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      border: Border(
        left: BorderSide(
          color: r.isMilestone ? AppColors.pine : AppColors.line,
          width: r.isMilestone ? 2.5 : 1,
        ),
        top: const BorderSide(color: AppColors.line),
        right: const BorderSide(color: AppColors.line),
        bottom: const BorderSide(color: AppColors.line),
      ),
      onTap: () => _openDetail(r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.isMilestone || r.isFavoriteRecord)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  if (r.isMilestone)
                    AppBadge.pine(
                      _msNames[r.milestoneCode] ?? '里程碑',
                      icon: Icons.workspace_premium,
                    ),
                  if (r.isFavoriteRecord) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.star, size: 14, color: AppColors.gold),
                  ],
                ],
              ),
            ),
          Text(
            '${DateFormat('HH:mm').format(r.recordTime)} · ${r.authorLabel}',
            style: AppText.meta,
          ),
          if (r.content.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(r.content, style: AppText.bodySmall, maxLines: 4, overflow: TextOverflow.ellipsis),
          ],
          if (r.tags.isNotEmpty) ...[
            const SizedBox(height: 9),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in r.tags.take(4))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.clayLight,
                      borderRadius: AppRadius.pill,
                    ),
                    child: Text(t,
                        style: const TextStyle(fontSize: 11, color: AppColors.clayDark)),
                  ),
              ],
            ),
          ],
          if (images.isNotEmpty) ...[
            const SizedBox(height: 10),
            _imageGrid(images),
          ],
          if (hasAudio || hasVideo) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (hasVideo)
                  const AppBadge(label: '视频', icon: Icons.videocam_outlined),
                if (hasVideo && hasAudio) const SizedBox(width: 6),
                if (hasAudio)
                  const AppBadge.clay('录音', icon: Icons.graphic_eq),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _imageGrid(List<MediaItem> images) {
    if (images.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AspectRatio(
          aspectRatio: 2 / 1,
          child: _img(images.first),
        ),
      );
    }
    final show = images.take(4).toList();
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: show.length == 2 ? 2 : 3,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (var i = 0; i < show.length; i++)
          Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _img(show[i]),
              ),
              if (i == 3 && images.length > 4)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text('+${images.length - 4}',
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                ),
            ],
          ),
      ],
    );
  }

  Widget _img(MediaItem m) {
    final f = File(p.join(_rootPath, m.localRelativePath));
    return Image.file(
      f,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(color: AppColors.line),
    );
  }

  // ==================== 交互 ====================

  Future<void> _openAdd() async {
    if (_baby == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddRecordPage(babyId: _baby!.id)),
    );
    load();
  }

  Future<void> _openDetail(GrowthRecord r) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecordDetailPage(recordUuid: r.uuid)),
    );
    load();
  }

  Future<void> _switchBaby() async {
    final babies = await AppDatabase.instance.getBabies();
    if (!mounted) return;
    if (babies.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('只有一个宝宝，可在「我的 → 宝宝管理」中添加')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            const Text('切换宝宝',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final b in babies)
              ListTile(
                leading: BabyAvatar(baby: b, size: 40, radius: 12),
                title: Text(b.babyName, style: AppText.itemTitle),
                subtitle: Text(
                  AgeCalculator.titleText(b.birthDate, DateTime.now()),
                  style: AppText.caption,
                ),
                trailing: b.id == _baby?.id
                    ? const Icon(Icons.check, color: AppColors.clay, size: 20)
                    : null,
                onTap: () async {
                  await AppDatabase.instance.setActiveBaby(b.id);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  load();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 排序小节
class _DaySection {
  final DateTime day;
  final String title;
  final List<GrowthRecord> items;
  _DaySection(this.day, this.title, this.items);
}

/// 缩略图
class _Thumb extends StatelessWidget {
  final MediaItem? media;
  final String rootPath;
  final double size;
  final double radius;

  const _Thumb({
    required this.media,
    required this.rootPath,
    this.size = 44,
    this.radius = 10,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: media == null
            ? Container(color: AppColors.clayLight)
            : Image.file(
                File(p.join(rootPath, media!.localRelativePath)),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: AppColors.clayLight),
              ),
      ),
    );
  }
}

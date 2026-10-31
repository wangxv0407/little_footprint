import 'package:flutter/material.dart';

import '../db/app_database.dart';
import '../models/baby_info.dart';
import '../models/growth_record.dart';
import '../models/media_item.dart';
import '../theme.dart';
import '../utils/age_calculator.dart';
import '../utils/date_group.dart';
import '../widgets/timeline_card.dart';
import 'add_record_page.dart';
import 'record_detail_page.dart';

class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  BabyInfo? _baby;
  List<GrowthRecord> _records = [];
  Map<String, List<MediaItem>> _medias = {};
  String _filter = '全部';
  bool _loading = true;

  static const _filters = ['全部', '照片', '录音', '视频'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDatabase.instance;
    final baby = await db.getBabyInfo();
    final records = await db.getRecords();
    final medias = <String, List<MediaItem>>{};
    for (final r in records) {
      medias[r.uuid] = await db.getMediaForRecord(r.uuid);
    }
    if (!mounted) return;
    setState(() {
      _baby = baby;
      _records = records;
      _medias = medias;
      _loading = false;
    });
  }

  List<GrowthRecord> get _filtered {
    switch (_filter) {
      case '照片':
        return _records
            .where((r) => _medias[r.uuid]?.any((m) => m.fileType == 'image') ?? false)
            .toList();
      case '录音':
        return _records
            .where((r) => _medias[r.uuid]?.any((m) => m.fileType == 'audio') ?? false)
            .toList();
      case '视频':
        return _records
            .where((r) => _medias[r.uuid]?.any((m) => m.fileType == 'video') ?? false)
            .toList();
      default:
        return _records;
    }
  }

  /// 按日期分组（保持倒序）
  List<(String, List<GrowthRecord>)> _grouped() {
    final now = DateTime.now();
    final result = <(String, List<GrowthRecord>)>[];
    for (final r in _filtered) {
      final g = DateGroup.classify(r.recordTime, now);
      if (result.isNotEmpty && result.last.$1 == g.title) {
        result.last.$2.add(r);
      } else {
        result.add((g.title, [r]));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final ageTitle = _baby == null
        ? '未配置'
        : AgeCalculator.titleText(_baby!.birthDate, DateTime.now());
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.child_care, color: AppColors.primary, size: 22),
            const SizedBox(width: 6),
            Text(
              '${_baby?.babyName ?? '宝宝'} · $ageTitle',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        // 档案/同步/设置 统一由底部导航进入，AppBar 不再放跳转图标
      ),
      body: Column(
        children: [
          // 应用主标题（对齐 UI 设计稿）
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
            child: Row(
              children: [
                Text(
                  '小脚印成长记',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          _filterBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _grouped().length,
                        itemBuilder: (context, gi) {
                          final (title, records) = _grouped()[gi];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 4, bottom: 10),
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              for (final r in records)
                                TimelineCard(
                                  record: r,
                                  medias: _medias[r.uuid] ?? const [],
                                  birthDate: _baby?.birthDate ?? DateTime.now(),
                                  onTap: () => _openDetail(r),
                                ),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AddRecordPage()));
          _load();
        },
        child: const Icon(Icons.add, size: 30),
      ),
    );
  }

  Widget _filterBar() {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: _filters.map((f) {
          final selected = _filter == f;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _filter = f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  f,
                  style: TextStyle(
                    fontSize: 14,
                    color: selected ? Colors.white : AppColors.secondaryText,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo_library_outlined, size: 64, color: Color(0xFFC8C8C8)),
          const SizedBox(height: 14),
          const Text(
            '还没有成长记录\n点击右下角 + ，记下宝宝第一个瞬间',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.secondaryText, height: 1.6),
          ),
        ],
      ),
    );
  }

  void _openDetail(GrowthRecord record) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecordDetailPage(recordUuid: record.uuid)),
    ).then((_) => _load());
  }
}

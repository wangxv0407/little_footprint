import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/app_database.dart';
import '../models/growth_record.dart';
import '../models/record_type.dart';
import '../theme.dart';
import '../utils/age_calculator.dart';
import '../widgets/common.dart';
import 'record_detail_page.dart';

/// 时间范围筛选
enum _TimeRange { all, thisYear, thisMonth }

/// 搜索页
class SearchPage extends StatefulWidget {
  final int babyId;

  const SearchPage({super.key, required this.babyId});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  List<GrowthRecord> _results = const [];
  List<(String, int)> _tagStats = const [];
  Map<String, String> _msNames = const {};
  DateTime? _babyBirth;

  _TimeRange _range = _TimeRange.all;
  RecordFilter _typeFilter = RecordFilter.all;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final db = AppDatabase.instance;
    final defs = await db.getMilestoneDefs();
    final stats = await db.getTagStats(widget.babyId);
    final baby = await db.getBabyById(widget.babyId);
    if (!mounted) return;
    setState(() {
      _msNames = {for (final d in defs) d.code: d.name};
      _tagStats = stats;
      _babyBirth = baby?.birthDate;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  Future<void> _search() async {
    final db = AppDatabase.instance;
    DateTime? from;
    final now = DateTime.now();
    switch (_range) {
      case _TimeRange.thisYear:
        from = DateTime(now.year, 1, 1);
      case _TimeRange.thisMonth:
        from = DateTime(now.year, now.month, 1);
      case _TimeRange.all:
        from = null;
    }
    final list = await db.searchRecords(
      widget.babyId,
      _ctrl.text,
      filter: _typeFilter,
      from: from,
    );
    if (!mounted) return;
    setState(() {
      _results = list;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _searchBar(),
            _filters(),
            Expanded(
              child: _ctrl.text.trim().isEmpty && !_searched
                  ? _tagCloud()
                  : _results.isEmpty
                      ? const EmptyState(
                          icon: Icons.search_off,
                          title: '没有找到相关记录',
                          subtitle: '试试更短的关键词，或换一个时间范围',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                              AppSpace.pageX, 4, AppSpace.pageX, 80),
                          itemCount: _results.length + 1,
                          itemBuilder: (context, i) {
                            if (i == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text('找到 ${_results.length} 条记录',
                                    style: AppText.caption),
                              );
                            }
                            return _resultCard(_results[i - 1]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.pageX, 8, AppSpace.sm, AppSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: AppDecor.card(radius: AppRadius.md),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 18, color: AppColors.ink3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      onChanged: (v) {
                        if (v.isEmpty) {
                          setState(() {
                            _searched = false;
                            _results = const [];
                          });
                        } else {
                          _search();
                        }
                      },
                      style: const TextStyle(fontSize: 14, color: AppColors.ink),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '搜索日记、标签、里程碑',
                        hintStyle: TextStyle(fontSize: 14, color: AppColors.ink3),
                      ),
                    ),
                  ),
                  if (_ctrl.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _ctrl.clear();
                        setState(() {
                          _searched = false;
                          _results = const [];
                        });
                      },
                      child: const Icon(Icons.cancel, size: 16, color: AppColors.ink3),
                    ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            style: TextButton.styleFrom(foregroundColor: AppColors.clay),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    const ranges = <(_TimeRange, String)>[
      (_TimeRange.all, '全部时间'),
      (_TimeRange.thisYear, '今年'),
      (_TimeRange.thisMonth, '本月'),
    ];
    const types = <(RecordFilter, String)>[
      (RecordFilter.all, '全部'),
      (RecordFilter.milestone, '里程碑'),
      (RecordFilter.photo, '有照片'),
      (RecordFilter.favorite, '收藏'),
    ];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageX),
        children: [
          for (final (r, label) in ranges)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: AppChip(
                  label: label,
                  selected: _range == r,
                  onTap: () {
                    setState(() => _range = r);
                    if (_ctrl.text.trim().isNotEmpty) _search();
                  },
                ),
              ),
            ),
          Container(
            width: 1,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            color: AppColors.line,
          ),
          for (final (t, label) in types)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: AppChip(
                  label: label,
                  selected: _typeFilter == t,
                  onTap: () {
                    setState(() => _typeFilter = t);
                    _search();
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tagCloud() {
    if (_tagStats.isEmpty) {
      return const EmptyState(
        icon: Icons.search,
        title: '输入关键词开始搜索',
        subtitle: '可以搜日记内容、标签，或者里程碑名称',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.pageX, 12, AppSpace.pageX, 80),
      children: [
        Text('按标签查找', style: AppText.eyebrow),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (tag, count) in _tagStats)
              AppChip(
                label: '$tag · $count',
                onTap: () {
                  _ctrl.text = tag;
                  _search();
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _resultCard(GrowthRecord r) {
    final kw = _ctrl.text.trim();
    final age = _babyBirth == null ? '' : AgeCalculator.fullText(_babyBirth!, r.recordTime);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => RecordDetailPage(recordUuid: r.uuid)),
          );
          _search();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (r.isMilestone) ...[
                  AppBadge.pine(
                    _msNames[r.milestoneCode] ?? '里程碑',
                    icon: Icons.workspace_premium,
                  ),
                  const SizedBox(width: 6),
                ],
                if (r.recordType == RecordType.vaccine) ...[
                  AppBadge.gold('疫苗'),
                  const SizedBox(width: 6),
                ],
                if (r.isFavoriteRecord) ...[
                  const Icon(Icons.star, size: 13, color: AppColors.gold),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    '${DateFormat('yyyy-MM-dd').format(r.recordTime)} · $age',
                    style: AppText.meta,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (r.content.isNotEmpty) ...[
              const SizedBox(height: 7),
              _highlight(r.content, kw, maxLines: 3),
            ],
            if (r.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in r.tags)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.clayLight,
                        borderRadius: AppRadius.pill,
                      ),
                      child: Text(t,
                          style: const TextStyle(fontSize: 10.5, color: AppColors.clayDark)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 关键词高亮
  Widget _highlight(String text, String keyword, {int maxLines = 3}) {
    if (keyword.isEmpty) {
      return Text(text,
          maxLines: maxLines, overflow: TextOverflow.ellipsis, style: AppText.bodySmall);
    }
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    final k = keyword.toLowerCase();
    var start = 0;
    while (true) {
      final idx = lower.indexOf(k, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(TextSpan(
        text: text.substring(idx, idx + k.length),
        style: const TextStyle(
          backgroundColor: Color(0xFFFBE3D5),
          color: AppColors.clayDark,
          fontWeight: FontWeight.w600,
        ),
      ));
      start = idx + k.length;
    }
    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: AppText.bodySmall, children: spans),
    );
  }
}

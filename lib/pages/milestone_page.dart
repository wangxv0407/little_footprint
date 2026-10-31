import 'package:flutter/material.dart';

import '../db/app_database.dart';
import '../models/baby_info.dart';
import '../models/milestone_def.dart';
import '../theme.dart';
import '../utils/age_calculator.dart';
import '../widgets/common.dart';
import 'add_record_page.dart';
import 'record_detail_page.dart';

/// 里程碑页：按分类展示已达成与待达成
class MilestonePage extends StatefulWidget {
  const MilestonePage({super.key});

  @override
  State<MilestonePage> createState() => MilestonePageState();
}

class MilestonePageState extends State<MilestonePage> {
  BabyInfo? _baby;
  List<MilestoneStatus> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final db = AppDatabase.instance;
    final baby = await db.getActiveBaby();
    if (baby == null) {
      if (!mounted) return;
      setState(() {
        _baby = null;
        _items = const [];
        _loading = false;
      });
      return;
    }
    final items = await db.getMilestoneStatuses(baby.id);
    if (!mounted) return;
    setState(() {
      _baby = baby;
      _items = items;
      _loading = false;
    });
  }

  int get _achievedCount => _items.where((e) => e.achieved).length;

  int get _monthAge {
    final baby = _baby;
    if (baby == null) return 0;
    final now = DateTime.now();
    var m = (now.year - baby.birthDate.year) * 12 + (now.month - baby.birthDate.month);
    if (now.day < baby.birthDate.day) m--;
    return m < 0 ? 0 : m;
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
                ? const EmptyState(icon: Icons.child_care, title: '还没有建档')
                : RefreshIndicator(
                    color: AppColors.clay,
                    onRefresh: load,
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        _header(),
                        _progressCard(),
                        for (final cat in MilestoneCategory.ordered) ..._categoryBlock(cat),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.pageX, 8, AppSpace.pageX, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('MILESTONES', style: AppText.eyebrow),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('里程碑', style: AppText.serifTitle()),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${_baby!.babyName.isEmpty ? '宝宝' : _baby!.babyName} · '
                  '${AgeCalculator.titleText(_baby!.birthDate, DateTime.now())}',
                  style: AppText.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _progressCard() {
    final total = _items.length;
    final achieved = _achievedCount;
    final ratio = total == 0 ? 0.0 : achieved / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.pageX, 0, AppSpace.pageX, 8),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('$achieved', style: AppText.metricNum(size: 26)),
                      const SizedBox(width: 5),
                      Text('/ $total 已达成', style: AppText.caption),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _hintText(achieved, total),
                    style: AppText.caption.copyWith(color: AppColors.ink2),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 46,
              height: 46,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: 1,
                    strokeWidth: 4,
                    color: AppColors.line,
                  ),
                  CircularProgressIndicator(
                    value: ratio,
                    strokeWidth: 4,
                    color: AppColors.pine,
                    strokeCap: StrokeCap.round,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _hintText(int achieved, int total) {
    if (total == 0) return '暂无里程碑库';
    if (achieved == 0) return '记录第一个里程碑开始';
    final thisMonth = _items
        .where((e) =>
            !e.achieved && e.def.monthMin <= _monthAge && e.def.monthMax >= _monthAge)
        .length;
    if (thisMonth > 0) return '本月有 $thisMonth 项可以关注';
    return '继续保持记录';
  }

  List<Widget> _categoryBlock(String category) {
    final list = _items.where((e) => e.def.category == category).toList();
    if (list.isEmpty) return const [];
    final done = list.where((e) => e.achieved).length;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.pageX, 18, AppSpace.pageX, 8),
        child: Row(
          children: [
            Text(
              MilestoneCategory.label(category),
              style: TextStyle(
                fontFamily: AppFonts.serif,
                fontFamilyFallback: AppFonts.serifFallback,
                fontSize: 13.5,
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(width: 8),
            Text('$done/${list.length}', style: AppText.caption),
            const SizedBox(width: 10),
            const Expanded(child: Divider(height: 1, color: AppColors.line)),
          ],
        ),
      ),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpace.pageX),
        decoration: AppDecor.card(),
        child: Column(
          children: [
            for (var i = 0; i < list.length; i++)
              _row(list[i], isLast: i == list.length - 1),
          ],
        ),
      ),
    ];
  }

  Widget _row(MilestoneStatus s, {bool isLast = false}) {
    final inWindow =
        !s.achieved && s.def.monthMin <= _monthAge && s.def.monthMax >= _monthAge;
    final achievedLabel = s.achieved
        ? '${_fmtDate(s.achievedAt!)} · '
            '${AgeCalculator.fullText(_baby!.birthDate, s.achievedAt!)}'
        : '建议 ${s.def.monthRangeLabel}';

    return InkWell(
      onTap: () => _onTapItem(s),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: s.achieved ? AppColors.pine : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: s.achieved ? AppColors.pine : AppColors.lineStrong,
                  width: 1.6,
                ),
              ),
              child: s.achieved
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.def.name,
                    style: AppText.itemTitle.copyWith(
                      color: s.achieved ? AppColors.ink2 : AppColors.ink,
                      fontWeight: s.achieved ? FontWeight.w400 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(achievedLabel, style: AppText.caption),
                ],
              ),
            ),
            if (inWindow)
              const AppBadge.clay('本月可关注')
            else if (s.achieved)
              const Icon(Icons.chevron_right, size: 18, color: AppColors.ink3)
            else
              const Icon(Icons.add, size: 17, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _onTapItem(MilestoneStatus s) async {
    if (s.achieved && s.recordUuid != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RecordDetailPage(recordUuid: s.recordUuid!)),
      );
      load();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddRecordPage(
          babyId: _baby!.id,
          initialMilestoneCode: s.def.code,
        ),
      ),
    );
    load();
  }
}

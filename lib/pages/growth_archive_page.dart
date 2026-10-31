import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../models/baby_info.dart';
import '../models/growth_metric.dart';
import '../theme.dart';
import '../utils/age_calculator.dart';
import '../widgets/common.dart';

/// 测量维度
enum _Dim { height, weight, head }

class _DimSpec {
  final String label;
  final String unit;
  final Color color;
  const _DimSpec(this.label, this.unit, this.color);
}

const _dims = <_Dim, _DimSpec>{
  _Dim.height: _DimSpec('身高', 'cm', AppColors.clay),
  _Dim.weight: _DimSpec('体重', 'kg', AppColors.pine),
  _Dim.head: _DimSpec('头围', 'cm', AppColors.gold),
};

/// 成长档案：曲线 + 统计 + 历史
class GrowthArchivePage extends StatefulWidget {
  const GrowthArchivePage({super.key});

  @override
  State<GrowthArchivePage> createState() => GrowthArchivePageState();
}

class GrowthArchivePageState extends State<GrowthArchivePage> {
  BabyInfo? _baby;
  List<GrowthMetric> _metrics = const [];
  _Dim _dim = _Dim.height;
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
        _metrics = const [];
        _loading = false;
      });
      return;
    }
    final list = await db.getMetrics(baby.id);
    if (!mounted) return;
    setState(() {
      _baby = baby;
      _metrics = list;
      _loading = false;
    });
  }

  double _valueOf(GrowthMetric m, _Dim d) => switch (d) {
        _Dim.height => m.height,
        _Dim.weight => m.weight,
        _Dim.head => m.headCircum,
      };

  List<double> get _series =>
      _metrics.map((m) => _valueOf(m, _dim)).where((v) => v > 0).toList();

  double get _latest => _series.isEmpty ? 0 : _series.last;

  double get _delta3m {
    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    final recent = _metrics.where((m) => m.metricTime.isAfter(cutoff)).toList();
    if (recent.length < 2) return 0;
    final first = _valueOf(recent.first, _dim);
    final last = _valueOf(recent.last, _dim);
    if (first <= 0 || last <= 0) return 0;
    return last - first;
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
                        _segmented(),
                        _chartCard(),
                        _stats(),
                        if (_metrics.isNotEmpty) _history(),
                        const SizedBox(height: 90),
                      ],
                    ),
                  ),
      ),
      floatingActionButton: _baby == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _addMetric,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('记录测量',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.pageX, 8, AppSpace.pageX, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('GROWTH', style: AppText.eyebrow),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('成长档案', style: AppText.serifTitle()),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  AgeCalculator.titleText(_baby!.birthDate, DateTime.now()),
                  style: AppText.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segmented() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpace.pageX),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFEFE7DA),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          for (final d in _Dim.values)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _dim = d),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _dim == d ? AppColors.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: _dim == d
                        ? const [
                            BoxShadow(
                                color: Color(0x142B2724),
                                blurRadius: 4,
                                offset: Offset(0, 1))
                          ]
                        : null,
                  ),
                  child: Text(
                    _dims[d]!.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: _dim == d ? FontWeight.w600 : FontWeight.w400,
                      color: _dim == d ? AppColors.ink : AppColors.ink2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chartCard() {
    final spec = _dims[_dim]!;
    final points = <FlSpot>[];
    for (var i = 0; i < _metrics.length; i++) {
      final v = _valueOf(_metrics[i], _dim);
      if (v > 0) points.add(FlSpot(points.length.toDouble(), v));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.pageX, AppSpace.md, AppSpace.pageX, 0),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _latest == 0 ? '—' : _latest.toStringAsFixed(1),
                  style: AppText.metricNum(size: 28),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(spec.unit, style: AppText.caption),
                ),
                const Spacer(),
                if (_delta3m != 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.pineLight,
                      borderRadius: AppRadius.pill,
                    ),
                    child: Text(
                      '近 3 月 ${_delta3m > 0 ? '+' : ''}${_delta3m.toStringAsFixed(1)}',
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.pine, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (points.length < 2)
              SizedBox(
                height: 140,
                child: Center(
                  child: Text(
                    points.isEmpty ? '还没有${spec.label}记录' : '再记录一次就能看到曲线了',
                    style: AppText.caption,
                  ),
                ),
              )
            else
              SizedBox(
                height: 156,
                child: LineChart(
                  LineChartData(
                    minY: _minY(points),
                    maxY: _maxY(points),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: _gridInterval(points),
                      getDrawingHorizontalLine: (_) =>
                          const FlLine(color: AppColors.line, strokeWidth: 1),
                    ),
                    titlesData: FlTitlesData(
                      topTitles:
                          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles:
                          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 34,
                          interval: _gridInterval(points),
                          getTitlesWidget: (v, meta) => Text(
                            v.toStringAsFixed(0),
                            style: const TextStyle(fontSize: 9.5, color: AppColors.ink3),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            final valid = _metrics.where((m) => _valueOf(m, _dim) > 0).toList();
                            if (i < 0 || i >= valid.length) return const SizedBox.shrink();
                            if (valid.length > 5 && i % 2 != 0) return const SizedBox.shrink();
                            final d = valid[i].metricTime;
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('${d.month}/${d.day}',
                                  style: const TextStyle(
                                      fontSize: 9.5, color: AppColors.ink3)),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => AppColors.ink,
                        getTooltipItems: (spots) => spots
                            .map((s) => LineTooltipItem(
                                  '${s.y.toStringAsFixed(1)}${spec.unit}',
                                  const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600),
                                ))
                            .toList(),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: points,
                        isCurved: true,
                        curveSmoothness: 0.28,
                        color: spec.color,
                        barWidth: 2.2,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, pct, bar, i) => FlDotCirclePainter(
                            radius: 3.2,
                            color: AppColors.card,
                            strokeColor: spec.color,
                            strokeWidth: 2,
                          ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              spec.color.withValues(alpha: 0.16),
                              spec.color.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _gridInterval(List<FlSpot> pts) {
    final values = pts.map((e) => e.y).toList();
    final span = values.reduce((a, b) => a > b ? a : b) -
        values.reduce((a, b) => a < b ? a : b);
    if (span <= 0) return 1;
    final step = span / 3;
    return step < 1 ? 1 : step.ceilToDouble();
  }

  double _minY(List<FlSpot> pts) {
    final min = pts.map((e) => e.y).reduce((a, b) => a < b ? a : b);
    return (min - _gridInterval(pts)).floorToDouble().clamp(0, double.infinity);
  }

  double _maxY(List<FlSpot> pts) {
    final max = pts.map((e) => e.y).reduce((a, b) => a > b ? a : b);
    return max + _gridInterval(pts) * 0.6;
  }

  Widget _stats() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.pageX, AppSpace.md, AppSpace.pageX, 0),
      child: Row(
        children: [
          _statTile('${_metrics.length}', '测量次数'),
          const SizedBox(width: 8),
          _statTile(
            _latest == 0 ? '—' : _latest.toStringAsFixed(1),
            '最新${_dims[_dim]!.label}',
          ),
          const SizedBox(width: 8),
          _statTile(
            _metrics.isEmpty
                ? '—'
                : '${DateTime.now().difference(_metrics.last.metricTime).inDays}',
            '距上次(天)',
          ),
        ],
      ),
    );
  }

  Widget _statTile(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: AppDecor.card(radius: AppRadius.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: AppText.metricNum(size: 18)),
            const SizedBox(height: 4),
            Text(label,
                style: AppText.caption.copyWith(fontSize: 10, letterSpacing: 0.6)),
          ],
        ),
      ),
    );
  }

  Widget _history() {
    final reversed = _metrics.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('历史测量'),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpace.pageX),
          decoration: AppDecor.card(),
          child: Column(
            children: [
              for (var i = 0; i < reversed.length; i++)
                _historyRow(reversed[i], isLast: i == reversed.length - 1),
            ],
          ),
        ),
      ],
    );
  }

  Widget _historyRow(GrowthMetric m, {bool isLast = false}) {
    final date =
        '${m.metricTime.year}-${m.metricTime.month.toString().padLeft(2, '0')}-${m.metricTime.day.toString().padLeft(2, '0')}';
    final age = _baby == null ? '' : AgeCalculator.titleText(_baby!.birthDate, m.metricTime);
    return InkWell(
      onTap: () => _confirmDelete(m),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(date,
                      style: const TextStyle(fontSize: 13.5, color: AppColors.ink)),
                  const SizedBox(height: 3),
                  Text(age, style: AppText.caption),
                ],
              ),
            ),
            Text(
              '${_fmtVal(m.height)} / ${_fmtVal(m.weight)} / ${_fmtVal(m.headCircum)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.ink2,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtVal(double v) => v == 0 ? '-' : v.toStringAsFixed(1);

  Future<void> _addMetric() async {
    final result = await showModalBottomSheet<(DateTime, double, double, double)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMetricSheet(babyId: _baby!.id),
    );
    if (result == null) return;
    final now = DateTime.now();
    final m = GrowthMetric(
      uuid: const Uuid().v4(),
      babyId: _baby!.id,
      metricTime: result.$1,
      height: result.$2,
      weight: result.$3,
      headCircum: result.$4,
      lastModifyTs: now.millisecondsSinceEpoch,
    );
    await AppDatabase.instance.upsertGrowthMetric(m);
    load();
  }

  Future<void> _confirmDelete(GrowthMetric m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: const Text('删除这次测量？', style: TextStyle(fontSize: 16)),
        content: Text(
          '${m.metricTime.year}-${m.metricTime.month}-${m.metricTime.day} 的记录将被删除。',
          style: const TextStyle(fontSize: 13, height: 1.7),
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
    await AppDatabase.instance.deleteMetricSoft(m.uuid);
    load();
  }
}

/// 添加测量
class _AddMetricSheet extends StatefulWidget {
  final int babyId;
  const _AddMetricSheet({required this.babyId});

  @override
  State<_AddMetricSheet> createState() => _AddMetricSheetState();
}

class _AddMetricSheetState extends State<_AddMetricSheet> {
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _head = TextEditingController();
  DateTime _time = DateTime.now();

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    _head.dispose();
    super.dispose();
  }

  void _submit() {
    final h = double.tryParse(_height.text.trim()) ?? 0;
    final w = double.tryParse(_weight.text.trim()) ?? 0;
    final hc = double.tryParse(_head.text.trim()) ?? 0;
    if (h <= 0 && w <= 0 && hc <= 0) return;
    Navigator.pop(context, (_time, h, w, hc));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: DateTime(now.year - 18),
      lastDate: now,
      helpText: '测量日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked != null) setState(() => _time = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: AppSpace.pageX,
        right: AppSpace.pageX,
        top: AppSpace.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpace.xl,
      ),
      decoration: const BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.lineStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          const Text('记录测量',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpace.lg),
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: AppDecor.card(radius: AppRadius.md),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 17, color: AppColors.clay),
                  const SizedBox(width: 10),
                  Text(
                    '${_time.year}-${_time.month.toString().padLeft(2, '0')}-${_time.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 14, color: AppColors.ink),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, size: 17, color: AppColors.ink3),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _field(_height, '身高', 'cm'),
              const SizedBox(width: 10),
              _field(_weight, '体重', 'kg'),
              const SizedBox(width: 10),
              _field(_head, '头围', 'cm'),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _submit, child: const Text('保存')),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String unit) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption),
          const SizedBox(height: 5),
          TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 15, color: AppColors.ink),
            decoration: InputDecoration(
              isDense: true,
              hintText: unit,
              hintStyle: const TextStyle(color: AppColors.ink3, fontSize: 14),
              filled: true,
              fillColor: AppColors.card,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.clay, width: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

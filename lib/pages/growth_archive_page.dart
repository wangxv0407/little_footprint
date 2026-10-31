import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../models/growth_metric.dart';
import '../theme.dart';

class GrowthArchivePage extends StatefulWidget {
  const GrowthArchivePage({super.key});

  @override
  State<GrowthArchivePage> createState() => _GrowthArchivePageState();
}

class _GrowthArchivePageState extends State<GrowthArchivePage> {
  List<GrowthMetric> _metrics = [];
  bool _loading = true;
  bool _showHeight = true;
  bool _showWeight = true;
  bool _showHead = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final metrics = await AppDatabase.instance.getMetrics();
    if (!mounted) return;
    setState(() {
      _metrics = metrics;
      _loading = false;
    });
  }

  Future<void> _addMetric() async {
    final result = await showModalBottomSheet<(double, double, double)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddMetricSheet(),
    );
    if (result == null) return;
    final now = DateTime.now();
    final m = GrowthMetric(
      uuid: const Uuid().v4(),
      metricTime: now,
      height: result.$1,
      weight: result.$2,
      headCircum: result.$3,
      lastModifyTs: DateTime.now().millisecondsSinceEpoch,
      isDeleted: 0,
    );
    await AppDatabase.instance.upsertGrowthMetric(m);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('成长档案'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMetric,
        icon: const Icon(Icons.add),
        label: const Text('添加测量'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _legendBar(),
                Expanded(
                  child: _metrics.isEmpty
                      ? const Center(
                          child: Text('还没有测量记录，点击右下角 + 添加',
                              style: TextStyle(color: AppColors.secondaryText)),
                        )
                      : _chart(),
                ),
                // 历史列表
                if (_metrics.isNotEmpty)
                  Container(
                    height: 160,
                    padding: const EdgeInsets.all(12),
                    child: ListView.builder(
                      itemCount: _metrics.length,
                      itemBuilder: (context, i) {
                        final m = _metrics[_metrics.length - 1 - i]; // 倒序
                        return ListTile(
                          dense: true,
                          title: Text(DateFormat('yyyy-MM-dd').format(m.metricTime)),
                          trailing: Text(
                            '${_f(m.height)}cm · ${_f(m.weight)}kg · ${_f(m.headCircum)}cm',
                            style: const TextStyle(fontSize: 13, color: AppColors.secondaryText),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }

  String _f(double v) => v == 0 ? '-' : v.toStringAsFixed(1);

  Widget _legendBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _legendItem('身高', AppColors.primary, _showHeight, (v) => setState(() => _showHeight = v)),
          const SizedBox(width: 16),
          _legendItem('体重', const Color(0xFFE07A5F), _showWeight, (v) => setState(() => _showWeight = v)),
          const SizedBox(width: 16),
          _legendItem('头围', const Color(0xFFE9C46A), _showHead, (v) => setState(() => _showHead = v)),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color, bool show, ValueChanged<bool> onChange) {
    return GestureDetector(
      onTap: () => onChange(!show),
      child: Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: show ? AppColors.textMain : AppColors.secondaryText,
              decoration: show ? TextDecoration.none : TextDecoration.lineThrough,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chart() {
    final lines = <LineChartBarData>[];
    final xs = List.generate(_metrics.length, (i) => i.toDouble());
    if (_showHeight) {
      lines.add(LineChartBarData(
        spots: _spots(xs, (m) => m.height, active: true),
        isCurved: true,
        color: AppColors.primary,
        barWidth: 2,
        dotData: const FlDotData(show: true),
      ));
    }
    if (_showWeight) {
      lines.add(LineChartBarData(
        spots: _spots(xs, (m) => m.weight, active: _showWeight),
        isCurved: true,
        color: const Color(0xFFE07A5F),
        barWidth: 2,
        dotData: const FlDotData(show: true),
      ));
    }
    if (_showHead) {
      lines.add(LineChartBarData(
        spots: _spots(xs, (m) => m.headCircum, active: _showHead),
        isCurved: true,
        color: const Color(0xFFE9C46A),
        barWidth: 2,
        dotData: const FlDotData(show: true),
      ));
    }
    if (lines.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: _maxValue(),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 36),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= _metrics.length) return const SizedBox.shrink();
                  final d = _metrics[idx].metricTime;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${d.month}/${d.day}',
                        style: const TextStyle(fontSize: 10, color: AppColors.secondaryText)),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: lines,
        ),
      ),
    );
  }

  double _maxValue() {
    double m = 0;
    for (final x in _metrics) {
      if (x.height > m) m = x.height;
      if (x.weight > m) m = x.weight;
      if (x.headCircum > m) m = x.headCircum;
    }
    return m == 0 ? 100 : m * 1.2;
  }

  List<FlSpot> _spots(List<double> xs, double Function(GrowthMetric) f, {required bool active}) {
    if (!active) return [];
    return [
      for (var i = 0; i < _metrics.length; i++)
        FlSpot(xs[i], f(_metrics[i]).toDouble()),
    ];
  }
}

class _AddMetricSheet extends StatefulWidget {
  const _AddMetricSheet();

  @override
  State<_AddMetricSheet> createState() => _AddMetricSheetState();
}

class _AddMetricSheetState extends State<_AddMetricSheet> {
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _head = TextEditingController();

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
    Navigator.pop(context, (h, w, hc));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('添加测量记录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _field(_height, '身高 (cm)'),
          const SizedBox(height: 10),
          _field(_weight, '体重 (kg)'),
          const SizedBox(height: 10),
          _field(_head, '头围 (cm)'),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: _submit, child: const Text('保存'))),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

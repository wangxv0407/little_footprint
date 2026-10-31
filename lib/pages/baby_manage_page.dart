import 'package:flutter/material.dart';

import '../db/app_database.dart';
import '../models/baby_info.dart';
import '../theme.dart';
import '../utils/age_calculator.dart';
import '../widgets/common.dart';
import 'baby_info_page.dart';

/// 宝宝管理：列表 / 切换 / 新增 / 编辑 / 删除
class BabyManagePage extends StatefulWidget {
  const BabyManagePage({super.key});

  @override
  State<BabyManagePage> createState() => _BabyManagePageState();
}

class _BabyManagePageState extends State<BabyManagePage> {
  List<BabyInfo> _babies = const [];
  Map<int, int> _counts = const {};
  int? _activeId;
  String _deviceRole = 'owner';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDatabase.instance;
    final babies = await db.getBabies();
    final active = await db.getActiveBaby();
    final role = await db.getDeviceRole();
    final counts = <int, int>{};
    for (final b in babies) {
      counts[b.id] = await db.countRecordsOfBaby(b.id);
    }
    if (!mounted) return;
    setState(() {
      _babies = babies;
      _counts = counts;
      _activeId = active?.id;
      _deviceRole = role;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.ink2),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('宝宝管理', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.clay),
            onPressed: () => _openEdit(null),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.clay))
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                const SizedBox(height: 6),
                for (final b in _babies) _babyCard(b),
                _addButton(),
                const SizedBox(height: AppSpace.xl),
                const SectionLabel('本机身份'),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: AppSpace.pageX),
                  decoration: AppDecor.card(),
                  child: InkWell(
                    onTap: _pickRole,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('我是', style: AppText.itemTitle),
                                const SizedBox(height: 3),
                                Text('用于标注每条记录的记录人', style: AppText.caption),
                              ],
                            ),
                          ),
                          Text(
                            AppDatabase.deviceRoleLabel(_deviceRole),
                            style: AppText.caption.copyWith(color: AppColors.ink),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, size: 18, color: AppColors.ink3),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageX),
                  child: Text(
                    '点击卡片可修改小名、出生日期和头像；不设置头像时使用默认的简笔头像。\n'
                    '切换宝宝后，时间轴、里程碑与成长档案会同步切换，最多可添加 6 个。',
                    style: AppText.caption.copyWith(height: 1.8),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  Widget _babyCard(BabyInfo b) {
    final isActive = b.id == _activeId;
    final days = DateTime.now().difference(b.birthDate).inDays;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.pageX, 0, AppSpace.pageX, 12),
      child: AppCard(
        padding: const EdgeInsets.all(15),
        onTap: () => _openEdit(b),
        border: Border(
          left: BorderSide(
            color: isActive ? AppColors.clay : AppColors.line,
            width: isActive ? 2.5 : 1,
          ),
          top: const BorderSide(color: AppColors.line),
          right: const BorderSide(color: AppColors.line),
          bottom: const BorderSide(color: AppColors.line),
        ),
        child: Row(
          children: [
            BabyAvatar(baby: b, size: 52, radius: 16),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        b.babyName.isEmpty ? '宝宝' : b.babyName,
                        style: AppText.serifTitle(size: 17),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 7),
                        const AppBadge.clay('当前'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${BabyInfo.fmtDate(b.birthDate)} · ${AgeCalculator.titleText(b.birthDate, DateTime.now())}'
                    ' · ${_counts[b.id] ?? 0} 条记录',
                    style: AppText.caption,
                  ),
                  if (isActive) ...[
                    const SizedBox(height: 2),
                    Text('出生第 $days 天', style: AppText.caption.copyWith(color: AppColors.ink3)),
                  ],
                ],
              ),
            ),
            if (!isActive)
              TextButton(
                onPressed: () async {
                  await AppDatabase.instance.setActiveBaby(b.id);
                  _load();
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.clay,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                child: const Text('切换'),
              )
            else
              const Icon(Icons.chevron_right, size: 18, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }

  Widget _addButton() {
    final canAdd = _babies.length < 6;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageX),
      child: GestureDetector(
        onTap: canAdd ? () => _openEdit(null) : null,
        child: Container(
          height: 54,
          decoration: AppDecor.dashed(),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 18, color: canAdd ? AppColors.clay : AppColors.ink3),
              const SizedBox(width: 6),
              Text(
                canAdd ? '添加宝宝' : '最多 6 个宝宝',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: canAdd ? AppColors.clay : AppColors.ink3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openEdit(BabyInfo? baby) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BabyInfoPage(initial: baby)),
    );
    _load();
  }

  Future<void> _pickRole() async {
    final picked = await showModalBottomSheet<String>(
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
            const Text('本机身份', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final (role, label) in [('owner', '爸爸'), ('partner', '妈妈')])
              ListTile(
                title: Text(label, style: AppText.itemTitle),
                trailing: _deviceRole == role
                    ? const Icon(Icons.check, color: AppColors.clay, size: 20)
                    : null,
                onTap: () => Navigator.pop(ctx, role),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await AppDatabase.instance.setDeviceRole(picked);
    _load();
  }
}

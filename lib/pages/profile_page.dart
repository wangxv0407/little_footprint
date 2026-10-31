import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/app_database.dart';
import '../models/baby_info.dart';
import '../services/backup_service.dart';
import '../services/media_service.dart';
import '../theme.dart';
import '../utils/age_calculator.dart';
import '../widgets/common.dart';
import 'baby_manage_page.dart';
import 'sync_page.dart';

/// 「我的」页：原来的设置页，承接低频但重要的操作
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => ProfilePageState();
}

class ProfilePageState extends State<ProfilePage> {
  BabyInfo? _baby;
  int _babyCount = 0;
  String _storageText = '计算中…';
  int _lastBackupTs = 0;
  int _recordCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final db = AppDatabase.instance;
    final baby = await db.getActiveBaby();
    final babies = await db.getBabies();
    final backupTs = await db.getLastBackupTs();
    final count = baby == null ? 0 : await db.countRecordsOfBaby(baby.id);
    if (!mounted) return;
    setState(() {
      _baby = baby;
      _babyCount = babies.length;
      _lastBackupTs = backupTs;
      _recordCount = count;
      _loading = false;
    });
    _calcStorage();
  }

  Future<void> _calcStorage() async {
    try {
      final root = await MediaService.instance.recordsRoot;
      var total = 0;
      await for (final e in root.list(recursive: true)) {
        if (e is File) total += await e.length();
      }
      if (!mounted) return;
      setState(() => _storageText = _fmtBytes(total));
    } catch (_) {
      if (!mounted) return;
      setState(() => _storageText = '—');
    }
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  /// 距上次备份的天数；从未备份返回 -1
  int get _backupAgeDays {
    if (_lastBackupTs == 0) return -1;
    final last = DateTime.fromMillisecondsSinceEpoch(_lastBackupTs);
    return DateTime.now().difference(last).inDays;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.clay))
            : ListView(
                padding: EdgeInsets.zero,
                children: [
                  _header(),
                  _babyCard(),
                  const SectionLabel('记录'),
                  _group([
                    _row(
                      icon: Icons.child_care,
                      tint: AppColors.pine,
                      title: '宝宝管理',
                      subtitle: '$_babyCount 个宝宝',
                      onTap: _openBabyManage,
                    ),
                  ]),
                  const SectionLabel('数据'),
                  _group([
                    _row(
                      icon: Icons.sync,
                      tint: AppColors.clay,
                      title: '双机同步',
                      subtitle: '局域网内两台手机互传，不经过服务器',
                      onTap: _openSync,
                    ),
                    _row(
                      icon: Icons.inventory_2_outlined,
                      tint: AppColors.clay,
                      title: '备份与恢复',
                      subtitle: _backupSubtitle,
                      subtitleColor: _backupAgeDays < 0 || _backupAgeDays > 30
                          ? AppColors.clay
                          : null,
                      onTap: _exportBackup,
                    ),
                    _row(
                      icon: Icons.storage_outlined,
                      tint: AppColors.pine,
                      title: '存储占用',
                      subtitle: '媒体文件占用空间',
                      trailingText: _storageText,
                      onTap: _calcStorage,
                    ),
                  ]),
                  const SectionLabel('关于'),
                  _group([
                    _row(
                      icon: Icons.info_outline,
                      tint: AppColors.ink2,
                      title: '关于本应用',
                      subtitle: '本地存储 · 局域网同步 · 无云端',
                      onTap: _about,
                    ),
                  ]),
                  const SizedBox(height: AppSpace.xl),
                  Center(
                    child: Text(
                      '小脚印成长记 v1.1.0\n所有数据只存在你的手机里',
                      textAlign: TextAlign.center,
                      style: AppText.caption.copyWith(height: 1.8),
                    ),
                  ),
                  const SizedBox(height: 90),
                ],
              ),
      ),
    );
  }

  String get _backupSubtitle {
    final days = _backupAgeDays;
    if (days < 0) return '还没有备份过，建议现在导出';
    if (days == 0) return '今天已备份';
    if (days > 30) return '距上次备份 $days 天，建议现在导出';
    return '$days 天前备份';
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.pageX, 8, AppSpace.pageX, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PROFILE', style: AppText.eyebrow),
          const SizedBox(height: 6),
          Text('我的', style: AppText.serifTitle()),
        ],
      ),
    );
  }

  Widget _babyCard() {
    final baby = _baby;
    if (baby == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageX),
        child: AppCard(
          onTap: _openBabyManage,
          child: Row(
            children: [
              const Icon(Icons.add_circle_outline, color: AppColors.clay),
              const SizedBox(width: 10),
              Text('添加宝宝', style: AppText.itemTitle),
            ],
          ),
        ),
      );
    }

    final days = DateTime.now().difference(baby.birthDate).inDays;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageX),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        color: const Color(0xFFFFFDFA),
        onTap: _openBabyManage,
        child: Row(
          children: [
            BabyAvatar(baby: baby, size: 54, radius: 16),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    baby.babyName.isEmpty ? '宝宝' : baby.babyName,
                    style: AppText.serifTitle(size: 18),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '出生第 $days 天 · ${AgeCalculator.titleText(baby.birthDate, DateTime.now())}'
                    ' · $_recordCount 条记录',
                    style: AppText.caption,
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

  Widget _group(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpace.pageX),
      decoration: AppDecor.card(),
      child: Column(children: children),
    );
  }

  Widget _row({
    required IconData icon,
    required Color tint,
    required String title,
    String? subtitle,
    Color? subtitleColor,
    String? trailingText,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.itemTitle),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppText.caption.copyWith(color: subtitleColor),
                    ),
                  ],
                ],
              ),
            ),
            if (trailingText != null)
              Text(trailingText, style: AppText.caption.copyWith(color: AppColors.ink2))
            else
              const Icon(Icons.chevron_right, size: 18, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }

  Future<void> _openBabyManage() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const BabyManagePage()));
    load();
  }

  Future<void> _openSync() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncPage()));
  }

  Future<void> _exportBackup() async {
    final age = _backupAgeDays;
    final desc = _lastBackupTs == 0
        ? '还没有备份过。'
        : '上次备份：${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(_lastBackupTs))}'
            '${age > 0 ? '（$age 天前）' : ''}。';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: const Text('导出本地备份', style: TextStyle(fontSize: 16)),
        content: Text(
          '$desc\n\n将打包数据库与媒体文件为一个 ZIP，保存到手机 Download 目录。\n'
          '建议每 30 天导出一次，并拷贝到电脑或移动硬盘。',
          style: const TextStyle(fontSize: 13, height: 1.7),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认导出')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final path = await BackupService.instance.exportBackupZip();
      await AppDatabase.instance.markBackedUp();
      if (!mounted) return;
      setState(() => _lastBackupTs = DateTime.now().millisecondsSinceEpoch);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已导出：$path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  void _about() {
    showAboutDialog(
      context: context,
      applicationName: '小脚印成长记',
      applicationVersion: '1.1.0',
      applicationIcon: const Icon(Icons.child_care, color: AppColors.clay, size: 40),
      children: const [
        Text(
          '本地优先的宝宝成长记录工具。照片、录音、视频、日记、身高体重全部保存在本机；'
          '两台安卓设备通过局域网手动同步，无云端、无账号、无外网请求。',
          style: TextStyle(fontSize: 13, height: 1.7),
        ),
      ],
    );
  }
}

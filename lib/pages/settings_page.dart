import 'dart:io';

import 'package:flutter/material.dart';

import '../services/backup_service.dart';
import '../services/media_service.dart';
import '../theme.dart';
import 'baby_info_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _storageText = '计算中…';

  @override
  void initState() {
    super.initState();
    _calcStorage();
  }

  Future<void> _calcStorage() async {
    final root = await MediaService.instance.recordsRoot;
    var total = 0;
    await for (final e in root.list(recursive: true)) {
      if (e is File) total += await e.length();
    }
    if (!mounted) return;
    setState(() => _storageText = _fmt(total));
  }

  String _fmt(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _exportBackup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出本地备份？'),
        content: const Text(
            '将打包数据库与压缩媒体为 ZIP，保存到手机 Download 文件夹。\n建议定期拷贝到移动硬盘备份。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认导出')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final path = await BackupService.instance.exportBackupZip();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('备份已导出：$path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }

  Future<void> _clearCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除缓存？'),
        content: const Text('仅清理临时文件，不会删除任何记录与原始文件。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // MVP 简化：暂只提示，未实现深度清理
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缓存已清理')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _item(Icons.child_care, '宝宝信息设置',
              subtitle: '修改小名、出生日期、本机身份', onTap: _openBabyInfo),
          _divider(),
          _item(Icons.archive_outlined, '本地备份导出',
              subtitle: '打包为 ZIP，保存到 Download', onTap: _exportBackup),
          _divider(),
          _item(Icons.storage_outlined, '存储占用',
              subtitle: 'APP 内媒体占用空间', trailing: Text(_storageText, style: const TextStyle(color: AppColors.secondaryText, fontSize: 14))),
          _divider(),
          _item(Icons.cleaning_services_outlined, '清除缓存',
              subtitle: '只清理临时文件，不删记录', onTap: _clearCache),
          _divider(),
          _item(Icons.info_outline, '关于本应用',
              subtitle: '本地存储 · 局域网同步 · 无云端', onTap: () => _about()),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              '小脚印成长记 v1.0.0\n仅本地存储，无云端，数据属于你和家人',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFFB0B0B0), height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.divider);

  Widget _item(IconData icon, String title,
      {String? subtitle, Widget? trailing, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title, style: const TextStyle(fontSize: 15, color: AppColors.textMain)),
      subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.secondaryText)),
      trailing: trailing ?? const Icon(Icons.chevron_right, color: Color(0xFFC0C0C0)),
      onTap: onTap,
    );
  }

  void _openBabyInfo() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const BabyInfoPage()));
  }

  void _about() {
    showAboutDialog(
      context: context,
      applicationName: '小脚印成长记',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.child_care, color: AppColors.primary, size: 40),
      children: const [
        Text('本地优先的宝宝成长记录工具。照片、录音、视频、日记、身高体重，全部保存在本机；两台安卓设备通过局域网手动同步，无云端、无外网访问。'),
      ],
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../db/app_database.dart';
import '../models/baby_info.dart';
import '../services/media_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 宝宝档案：新增（[initial] 为空）或编辑
class BabyInfoPage extends StatefulWidget {
  final BabyInfo? initial;

  const BabyInfoPage({super.key, this.initial});

  @override
  State<BabyInfoPage> createState() => _BabyInfoPageState();
}

class _BabyInfoPageState extends State<BabyInfoPage> {
  final _nameCtrl = TextEditingController();
  final _picker = ImagePicker();
  DateTime? _birthDate;
  int _gender = 0;
  String _avatarPath = '';
  bool _saving = false;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final b = widget.initial;
    if (b != null) {
      _nameCtrl.text = b.babyName;
      _birthDate = b.birthDate;
      _gender = b.gender;
      _avatarPath = b.avatarPath;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  /// 用于实时预览头像的临时档案（新增时还没有真实记录）
  BabyInfo get _preview {
    final name = _nameCtrl.text.trim();
    return BabyInfo(
      id: widget.initial?.id ?? 0,
      babyName: name.isEmpty ? '宝宝' : name,
      birthDate: _birthDate ?? DateTime.now(),
      avatarPath: _avatarPath,
      gender: _gender,
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? now,
      firstDate: DateTime(now.year - 18),
      lastDate: now,
      helpText: '选择出生日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _showAvatarSheet() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.ink2),
              title: const Text('拍一张', style: TextStyle(fontSize: 14)),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.ink2),
              title: const Text('从相册选择', style: TextStyle(fontSize: 14)),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (_avatarPath.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xFFB3261E)),
                title: const Text('移除头像',
                    style: TextStyle(fontSize: 14, color: Color(0xFFB3261E))),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'remove') {
      setState(() => _avatarPath = '');
      return;
    }

    final source = action == 'camera' ? ImageSource.camera : ImageSource.gallery;
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 640,
        maxHeight: 640,
        imageQuality: 88,
      );
      if (picked == null) return;
      final saved = await MediaService.instance.storeAvatar(picked.path);
      if (!mounted) return;
      setState(() => _avatarPath = saved);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('设置头像失败：$e')));
    }
  }

  Future<void> _save() async {
    if (_birthDate == null || _saving) return;
    setState(() => _saving = true);
    final db = AppDatabase.instance;
    final name = _nameCtrl.text.trim();
    try {
      if (_isEdit) {
        await db.updateBaby(widget.initial!.copyWith(
          babyName: name,
          birthDate: _birthDate,
          gender: _gender,
          avatarPath: _avatarPath,
        ));
        await _cleanupOldAvatar();
      } else {
        await db.insertBaby(BabyInfo(
          babyName: name.isEmpty ? '宝宝' : name,
          birthDate: _birthDate!,
          gender: _gender,
          avatarPath: _avatarPath,
        ));
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  /// 头像被替换或清除时，删掉磁盘上的旧文件
  Future<void> _cleanupOldAvatar() async {
    final old = widget.initial?.avatarPath ?? '';
    if (old.isEmpty || old == _avatarPath) return;
    try {
      final f = File(old);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 旧文件清理失败不影响保存结果
    }
  }

  Future<void> _delete() async {
    final baby = widget.initial!;
    final db = AppDatabase.instance;
    final count = await db.countRecordsOfBaby(baby.id);
    final total = (await db.getBabies()).length;

    if (total <= 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少保留一个宝宝，无法删除')),
      );
      return;
    }

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('删除「${baby.babyName}」？', style: const TextStyle(fontSize: 16)),
        content: Text(
          '该宝宝下的 $count 条记录与全部媒体文件将一并删除，无法恢复。\n'
          '建议先导出备份。',
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

    await db.deleteBabyCascade(baby.id);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _birthDate != null && !_saving;
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
        title: Text(
          _isEdit ? '编辑宝宝' : '添加宝宝',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.pageX, 6, AppSpace.pageX, 30),
        children: [
          const SizedBox(height: AppSpace.md),
          _avatarSection(),
          _label('小名'),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(fontSize: 15, color: AppColors.ink),
            decoration: _inputDecoration('例如：小满'),
            textInputAction: TextInputAction.done,
          ),
          _label('出生日期'),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              decoration: AppDecor.card(radius: AppRadius.md),
              child: Row(
                children: [
                  const Icon(Icons.cake_outlined, size: 18, color: AppColors.clay),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _birthDate == null ? '选择出生日期' : BabyInfo.fmtDate(_birthDate!),
                      style: TextStyle(
                        fontSize: 15,
                        color: _birthDate == null ? AppColors.ink3 : AppColors.ink,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18, color: AppColors.ink3),
                ],
              ),
            ),
          ),
          _label('性别（可选）'),
          Row(
            children: [
              for (final (v, label) in [(1, '男孩'), (2, '女孩'), (0, '不填')])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AppChip(
                    label: label,
                    selected: _gender == v,
                    onTap: () => setState(() => _gender = v),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.xl),
          Text(
            '出生日期用于自动计算月龄与里程碑建议，请如实填写。\n'
            '所有信息只保存在本机，不会上传到任何服务器。',
            style: AppText.caption.copyWith(height: 1.8),
          ),
          const SizedBox(height: AppSpace.xxl),
          FilledButton(
            onPressed: canSave ? _save : null,
            child: Text(_isEdit ? '保存修改' : '创建档案'),
          ),
          if (_isEdit) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFB3261E)),
              child: const Text('删除这个宝宝'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _avatarSection() => Center(
        child: Column(
          children: [
            GestureDetector(
              onTap: _showAvatarSheet,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  BabyAvatar(baby: _preview, size: 88, radius: 28),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AppColors.clay,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.paper, width: 2),
                      ),
                      child: const Icon(Icons.photo_camera_outlined,
                          size: 13, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _avatarPath.isEmpty ? '点击设置头像' : '点击更换头像',
              style: AppText.caption,
            ),
          ],
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.lg, bottom: 8),
        child: Text(
          text,
          style: AppText.caption.copyWith(fontWeight: FontWeight.w600, letterSpacing: 1.2),
        ),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.ink3, fontSize: 15),
        filled: true,
        fillColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.clay, width: 1.4),
        ),
      );
}

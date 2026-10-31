import 'package:flutter/material.dart';

import '../db/app_database.dart';
import '../models/baby_info.dart';
import '../theme.dart';

/// 首次启动引导：建档并选择本机身份
class SplashPage extends StatefulWidget {
  final VoidCallback onReady;

  const SplashPage({super.key, required this.onReady});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final _nameCtrl = TextEditingController();
  DateTime? _birthDate;
  String _role = 'owner';
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
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

  Future<void> _start() async {
    if (_birthDate == null || _saving) return;
    setState(() => _saving = true);
    final db = AppDatabase.instance;
    final name = _nameCtrl.text.trim();
    try {
      await db.insertBaby(BabyInfo(
        babyName: name.isEmpty ? '宝宝' : name,
        birthDate: _birthDate!,
      ));
      await db.setDeviceRole(_role);
      if (!mounted) return;
      widget.onReady();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('创建档案失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canStart = _birthDate != null && !_saving;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.pageX, 20, AppSpace.pageX, 30),
          children: [
            Center(child: _illustration()),
            const SizedBox(height: 26),
            Text(
              '记住每一个\n小小的第一次',
              textAlign: TextAlign.center,
              style: AppText.serifTitle(size: 26, height: 1.45),
            ),
            const SizedBox(height: 10),
            Text(
              '照片、声音、身高体重，\n全部留在这台手机里。',
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(height: 1.9, fontSize: 12.5),
            ),
            const SizedBox(height: 30),
            _label('宝宝小名'),
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
            _label('我是'),
            Row(
              children: [
                for (final (role, label) in [('owner', '爸爸'), ('partner', '妈妈')])
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: role == 'owner' ? 10 : 0),
                      child: GestureDetector(
                        onTap: () => setState(() => _role = role),
                        child: Container(
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _role == role ? AppColors.clay : AppColors.card,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                              color: _role == role ? AppColors.clay : AppColors.line,
                            ),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _role == role ? Colors.white : AppColors.ink2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.xxl),
            FilledButton(
              onPressed: canStart ? _start : null,
              child: Text(_saving ? '创建中…' : '开始记录'),
            ),
            const SizedBox(height: 14),
            Text(
              '所有数据只存在你的手机里，不会上传到任何服务器',
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _illustration() {
    return SizedBox(
      width: 148,
      height: 148,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 148,
            height: 148,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.line, width: 1.2),
            ),
          ),
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.clayLight,
            ),
          ),
          const Icon(Icons.child_care, size: 46, color: AppColors.clay),
        ],
      ),
    );
  }

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

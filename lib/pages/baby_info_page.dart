import 'package:flutter/material.dart';

import '../db/app_database.dart';
import '../models/baby_info.dart';
import '../theme.dart';
import 'timeline_page.dart';

class BabyInfoPage extends StatefulWidget {
  const BabyInfoPage({super.key});

  @override
  State<BabyInfoPage> createState() => _BabyInfoPageState();
}

class _BabyInfoPageState extends State<BabyInfoPage> {
  final _nameCtrl = TextEditingController();
  DateTime? _birthDate;
  String _role = 'husband';

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
      firstDate: DateTime(now.year - 3),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
    }
  }

  Future<void> _save() async {
    if (_birthDate == null) return;
    final info = BabyInfo(
      id: BabyInfo.fixedId,
      babyName: _nameCtrl.text.trim(),
      birthDate: _birthDate!,
      deviceRole: _role,
    );
    await AppDatabase.instance.saveBabyInfo(info);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const TimelinePage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _birthDate != null;
    return Scaffold(
      appBar: AppBar(title: const Text('宝宝信息')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('小名', style: TextStyle(color: AppColors.secondaryText, fontSize: 14)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                hintText: '例如：安安',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('出生日期（用于自动计算月龄）',
                style: TextStyle(color: AppColors.secondaryText, fontSize: 14)),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cake_outlined, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _birthDate == null
                            ? '选择出生日期'
                            : '${_birthDate!.year}-${_birthDate!.month.toString().padLeft(2, '0')}-${_birthDate!.day.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 15,
                          color: _birthDate == null ? AppColors.secondaryText : AppColors.textMain,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('本机身份', style: TextStyle(color: AppColors.secondaryText, fontSize: 14)),
            const SizedBox(height: 6),
            Row(
              children: [
                _roleCard('husband', '爸爸设备', Icons.person),
                const SizedBox(width: 12),
                _roleCard('wife', '妈妈设备', Icons.person_outline),
              ],
            ),
            const SizedBox(height: 40),
            FilledButton(
              onPressed: canSave ? _save : null,
              child: const Text('保存并进入首页'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleCard(String role, String label, IconData icon) {
    final selected = _role == role;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _role = role),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: selected ? AppColors.lightGreen : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? AppColors.primary : AppColors.secondaryText),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: selected ? AppColors.primary : AppColors.secondaryText,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

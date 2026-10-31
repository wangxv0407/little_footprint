import 'package:flutter/material.dart';

import '../theme.dart';
import 'growth_archive_page.dart';
import 'settings_page.dart';
import 'sync_page.dart';
import 'timeline_page.dart';

/// 底部导航主壳：首页 / 档案 / 同步 / 设置 四个 Tab（对齐 UI 设计稿）
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          TimelinePage(),
          GrowthArchivePage(),
          SyncPage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: const Color(0xFFB0B0B0),
        backgroundColor: Colors.white,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: '首页',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.query_stats_outlined),
            activeIcon: Icon(Icons.query_stats),
            label: '档案',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sync_outlined),
            activeIcon: Icon(Icons.sync),
            label: '同步',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

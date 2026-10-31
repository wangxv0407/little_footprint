import 'package:flutter/material.dart';

import '../theme.dart';
import 'growth_archive_page.dart';
import 'milestone_page.dart';
import 'profile_page.dart';
import 'timeline_page.dart';

/// 底部导航主壳。
///
/// 四个一级入口：时间轴 / 里程碑 / 档案 / 我的。
/// 「双机同步」不再占一级位置——它是低频操作，降为「我的」内的二级页。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = <_TabSpec>[
    _TabSpec('时间轴', Icons.view_agenda_outlined, Icons.view_agenda),
    _TabSpec('里程碑', Icons.workspace_premium_outlined, Icons.workspace_premium),
    _TabSpec('档案', Icons.show_chart, Icons.show_chart),
    _TabSpec('我的', Icons.person_outline, Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          TimelinePage(),
          MilestonePage(),
          GrowthArchivePage(),
          ProfilePage(),
        ],
      ),
      bottomNavigationBar: _buildNav(),
    );
  }

  Widget _buildNav() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset - 4 : 0),
      decoration: const BoxDecoration(
        color: Color(0xF0FBF8F3),
        border: Border(top: BorderSide(color: Color(0x0E2B2724), width: 1)),
      ),
      child: SizedBox(
        height: 62,
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++) _navItem(i),
          ],
        ),
      ),
    );
  }

  Widget _navItem(int i) {
    final tab = _tabs[i];
    final selected = _index == i;
    final color = selected ? AppColors.clay : const Color(0xFFA69C8F);
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _index = i),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 38,
              height: 25,
              decoration: BoxDecoration(
                color: selected ? AppColors.clayLight : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(
                selected ? tab.activeIcon : tab.icon,
                size: 22,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.4,
                height: 1.2,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabSpec {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _TabSpec(this.label, this.icon, this.activeIcon);
}

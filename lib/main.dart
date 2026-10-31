import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'db/app_database.dart';
import 'pages/home_shell.dart';
import 'pages/splash_page.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 预初始化数据库
  await AppDatabase.instance.database;
  runApp(const LittleFootprintApp());
}

class LittleFootprintApp extends StatefulWidget {
  const LittleFootprintApp({super.key});

  @override
  State<LittleFootprintApp> createState() => _LittleFootprintAppState();
}

class _LittleFootprintAppState extends State<LittleFootprintApp> {
  bool _hasConfig = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final info = await AppDatabase.instance.getBabyInfo();
    if (mounted) {
      setState(() => _hasConfig = info != null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '小脚印成长记',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // 中文本地化：让 showDatePicker / showAboutDialog 等系统组件显示中文
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      locale: const Locale('zh'),
      home: _hasConfig ? const HomeShell() : const SplashPage(),
    );
  }
}

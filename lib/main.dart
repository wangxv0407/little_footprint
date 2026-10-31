import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'db/app_database.dart';
import 'pages/home_shell.dart';
import 'pages/splash_page.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 预初始化数据库（含 v1 → v2 迁移）
  await AppDatabase.instance.database;
  runApp(const LittleFootprintApp());
}

class LittleFootprintApp extends StatefulWidget {
  const LittleFootprintApp({super.key});

  @override
  State<LittleFootprintApp> createState() => _LittleFootprintAppState();
}

class _LittleFootprintAppState extends State<LittleFootprintApp> {
  bool? _hasBaby;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final baby = await AppDatabase.instance.getActiveBaby();
    if (!mounted) return;
    setState(() => _hasBaby = baby != null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '小脚印成长记',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      locale: const Locale('zh'),
      home: switch (_hasBaby) {
        null => const Scaffold(
            backgroundColor: AppColors.paper,
            body: Center(child: CircularProgressIndicator(color: AppColors.clay)),
          ),
        true => const HomeShell(),
        false => SplashPage(onReady: _loadConfig),
      },
    );
  }
}

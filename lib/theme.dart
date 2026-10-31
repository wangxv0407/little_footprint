import 'package:flutter/material.dart';

/// 设计 token —— 与 `design/ui-design-v1.1.html` 一一对应。
///
/// 视觉基调：手帐与纸张。暖米白纸底、陶土红作行动色、
/// 松绿只用于里程碑与达成态，形成专属语义。
class AppColors {
  // ---------- 纸张与描边 ----------
  /// 页面底色（暖米白纸）
  static const Color paper = Color(0xFFFBF8F3);

  /// 卡片白
  static const Color card = Color(0xFFFFFFFF);

  /// 卡片描边
  static const Color line = Color(0xFFEDE5D8);

  /// 较强的描边（输入框、虚线框）
  static const Color lineStrong = Color(0xFFE1D7C5);

  // ---------- 文字 ----------
  /// 主文字，对比度 12.6:1
  static const Color ink = Color(0xFF2B2724);

  /// 次要文字，对比度 4.7:1
  static const Color ink2 = Color(0xFF7C7369);

  /// 辅助文字，仅用于非关键信息
  static const Color ink3 = Color(0xFFB3A99D);

  // ---------- 主行动色（陶土） ----------
  static const Color clay = Color(0xFFBF5B3B);
  static const Color clayLight = Color(0xFFF7E8E1);
  static const Color clayDark = Color(0xFF9C4526);

  // ---------- 里程碑与达成态（松绿） ----------
  static const Color pine = Color(0xFF2E5245);
  static const Color pineLight = Color(0xFFE4EDE7);

  // ---------- 点缀（暖金） ----------
  static const Color gold = Color(0xFFD9A34E);
  static const Color goldLight = Color(0xFFFAF0DD);

  /// 记录人 / 时间等极小号辅助文字
  static const Color faint = Color(0xFFB0A69A);

  // ========== 兼容旧命名（逐步迁移，勿在新代码使用） ==========
  @Deprecated('用 paper')
  static const Color background = paper;
  @Deprecated('用 clay')
  static const Color primary = clay;
  @Deprecated('用 clayDark')
  static const Color primaryDark = clayDark;
  @Deprecated('用 ink2')
  static const Color secondaryText = ink2;
  @Deprecated('用 line')
  static const Color divider = line;
  @Deprecated('用 ink')
  static const Color textMain = ink;
  @Deprecated('用 clayLight')
  static const Color lightGreen = clayLight;
}

/// 字体族。
///
/// 中文衬线在 Android 上通过逻辑族名 `serif` 落到 Noto Serif CJK；
/// 若后续把 Noto Serif SC 放进 assets，只需把 [serif] 改为对应 family 名。
class AppFonts {
  static const String serif = 'serif';
  static const List<String> serifFallback = <String>[
    'Noto Serif CJK SC',
    'Noto Serif SC',
    'Songti SC',
    'STSong',
  ];
}

/// 文本样式。命名按用途而非尺寸，避免实现时二次判断。
class AppText {
  /// 衬线标题（宝宝名、页面大标题）
  static TextStyle serifTitle({
    double size = 21,
    FontWeight weight = FontWeight.w600,
    Color color = AppColors.ink,
    double height = 1.3,
  }) =>
      TextStyle(
        fontFamily: AppFonts.serif,
        fontFamilyFallback: AppFonts.serifFallback,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: 0.3,
      );

  /// 页面小标签（全大写西文，如 MILESTONES）
  static const TextStyle eyebrow = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.ink3,
    letterSpacing: 2.0,
    height: 1.4,
  );

  /// 正文
  static const TextStyle body = TextStyle(
    fontSize: 13.5,
    color: AppColors.ink,
    height: 1.72,
  );

  /// 正文（列表卡片内稍小）
  static const TextStyle bodySmall = TextStyle(
    fontSize: 13,
    color: AppColors.ink,
    height: 1.7,
  );

  /// 列表主标题
  static const TextStyle itemTitle = TextStyle(
    fontSize: 14,
    color: AppColors.ink,
    height: 1.4,
  );

  /// 辅助说明
  static const TextStyle caption = TextStyle(
    fontSize: 11,
    color: AppColors.ink3,
    height: 1.5,
  );

  /// 时间 / 记录人 等元信息
  static const TextStyle meta = TextStyle(
    fontSize: 10.5,
    color: AppColors.ink3,
    height: 1.4,
    letterSpacing: 0.2,
  );

  /// 数字强调（测量值）
  static TextStyle metricNum({double size = 28, Color color = AppColors.ink}) => TextStyle(
        fontFamily: AppFonts.serif,
        fontFamilyFallback: AppFonts.serifFallback,
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color,
        height: 1.1,
      );
}

/// 间距（4 为基数）
class AppSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;

  /// 页面左右安全边距
  static const double pageX = 20;
}

/// 圆角
class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 22;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

/// 复用装饰
class AppDecor {
  /// 标准卡片：白底 + 1px 描边，不用重投影
  static BoxDecoration card({Color color = AppColors.card, double radius = AppRadius.lg}) =>
      BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.line, width: 1),
      );

  /// 无描边卡片（用于需要悬浮感的场景）
  static BoxDecoration softCard({double radius = AppRadius.lg}) => BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(color: Color(0x0D2B2724), blurRadius: 6, offset: Offset(0, 2)),
          BoxShadow(color: Color(0x0F2B2724), blurRadius: 32, offset: Offset(0, 12)),
        ],
      );

  /// 虚线框（添加媒体、添加宝宝）
  static BoxDecoration dashed({double radius = AppRadius.md}) => BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.lineStrong, width: 1.4),
      );
}

/// 全局主题。
///
/// 刻意只设置最稳定的字段（colorScheme / scaffoldBackgroundColor / 字体），
/// 组件级样式由各页面显式指定——避免 Flutter 版本间
/// `AppBarTheme` / `CardTheme` → `*ThemeData` 的改名冲突。
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.clay,
    primary: AppColors.clay,
    onPrimary: Colors.white,
    secondary: AppColors.pine,
    surface: AppColors.paper,
    onSurface: AppColors.ink,
    error: const Color(0xFFB3261E),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.paper,
    splashFactory: InkSparkle.splashFactory,
    textTheme: const TextTheme(
      bodyMedium: AppText.body,
      bodySmall: AppText.caption,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.clay,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.lineStrong),
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.clay,
      foregroundColor: Colors.white,
      elevation: 6,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.line,
      thickness: 1,
      space: 1,
    ),
  );
}

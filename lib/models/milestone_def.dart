/// 里程碑分类
class MilestoneCategory {
  static const String motorGross = 'motor_gross';
  static const String motorFine = 'motor_fine';
  static const String language = 'language';
  static const String social = 'social';
  static const String cognition = 'cognition';

  /// 展示顺序
  static const List<String> ordered = [
    motorGross,
    motorFine,
    language,
    social,
    cognition,
  ];

  static String label(String code) => switch (code) {
        motorGross => '大运动',
        motorFine => '精细动作',
        language => '语言',
        social => '社交',
        cognition => '认知',
        _ => '其他',
      };
}

/// 里程碑定义（预置库或自定义）
class MilestoneDef {
  final String code;
  final String category;
  final String name;

  /// 建议达成月龄区间
  final int monthMin;
  final int monthMax;

  /// 1 = 预置，0 = 用户自定义
  final int isPreset;
  final int sortOrder;

  const MilestoneDef({
    required this.code,
    required this.category,
    required this.name,
    this.monthMin = 0,
    this.monthMax = 36,
    this.isPreset = 1,
    this.sortOrder = 0,
  });

  String get monthRangeLabel => monthMax >= 36 ? '$monthMin 月起' : '$monthMin–$monthMax 月';

  factory MilestoneDef.fromMap(Map<String, dynamic> map) => MilestoneDef(
        code: map['code'] as String,
        category: map['category'] as String? ?? MilestoneCategory.motorGross,
        name: map['name'] as String? ?? '',
        monthMin: map['month_min'] as int? ?? 0,
        monthMax: map['month_max'] as int? ?? 36,
        isPreset: map['is_preset'] as int? ?? 1,
        sortOrder: map['sort_order'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'code': code,
        'category': category,
        'name': name,
        'month_min': monthMin,
        'month_max': monthMax,
        'is_preset': isPreset,
        'sort_order': sortOrder,
      };
}

/// 里程碑 + 该宝宝的达成情况（视图模型）
class MilestoneStatus {
  final MilestoneDef def;

  /// 达成时间；null 表示未达成
  final DateTime? achievedAt;

  /// 达成时对应的记录 uuid
  final String? recordUuid;

  const MilestoneStatus({
    required this.def,
    this.achievedAt,
    this.recordUuid,
  });

  bool get achieved => achievedAt != null;
}

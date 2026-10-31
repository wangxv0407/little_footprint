/// 成长指标（身高/体重/头围测量）
class GrowthMetric {
  final String uuid;

  /// 归属宝宝（v2 起）
  final int babyId;

  final DateTime metricTime;

  /// 身高 cm
  final double height;

  /// 体重 kg
  final double weight;

  /// 头围 cm
  final double headCircum;

  final int lastModifyTs;

  /// 0 正常 / 1 软删除
  final int isDeleted;

  const GrowthMetric({
    required this.uuid,
    this.babyId = 1,
    required this.metricTime,
    this.height = 0,
    this.weight = 0,
    this.headCircum = 0,
    this.lastModifyTs = 0,
    this.isDeleted = 0,
  });

  GrowthMetric copyWith({
    String? uuid,
    int? babyId,
    DateTime? metricTime,
    double? height,
    double? weight,
    double? headCircum,
    int? lastModifyTs,
    int? isDeleted,
  }) =>
      GrowthMetric(
        uuid: uuid ?? this.uuid,
        babyId: babyId ?? this.babyId,
        metricTime: metricTime ?? this.metricTime,
        height: height ?? this.height,
        weight: weight ?? this.weight,
        headCircum: headCircum ?? this.headCircum,
        lastModifyTs: lastModifyTs ?? this.lastModifyTs,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  factory GrowthMetric.fromMap(Map<String, dynamic> map) => GrowthMetric(
        uuid: map['uuid'] as String,
        babyId: map['baby_id'] as int? ?? 1,
        metricTime: DateTime.parse(map['metric_time'] as String),
        height: (map['height'] as num?)?.toDouble() ?? 0,
        weight: (map['weight'] as num?)?.toDouble() ?? 0,
        headCircum: (map['head_circum'] as num?)?.toDouble() ?? 0,
        lastModifyTs: map['last_modify_ts'] as int? ?? 0,
        isDeleted: map['is_deleted'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'uuid': uuid,
        'baby_id': babyId,
        'metric_time': metricTime.toIso8601String(),
        'height': height,
        'weight': weight,
        'head_circum': headCircum,
        'last_modify_ts': lastModifyTs,
        'is_deleted': isDeleted,
      };
}

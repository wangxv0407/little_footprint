/// 成长指标（身高/体重/头围测量）
class GrowthMetric {
  final String uuid;
  final DateTime metricTime;
  final double height; // cm
  final double weight; // kg
  final double headCircum; // cm
  final int lastModifyTs;
  final int isDeleted;

  const GrowthMetric({
    required this.uuid,
    required this.metricTime,
    required this.height,
    required this.weight,
    required this.headCircum,
    required this.lastModifyTs,
    required this.isDeleted,
  });

  GrowthMetric copyWith({
    String? uuid,
    DateTime? metricTime,
    double? height,
    double? weight,
    double? headCircum,
    int? lastModifyTs,
    int? isDeleted,
  }) =>
      GrowthMetric(
        uuid: uuid ?? this.uuid,
        metricTime: metricTime ?? this.metricTime,
        height: height ?? this.height,
        weight: weight ?? this.weight,
        headCircum: headCircum ?? this.headCircum,
        lastModifyTs: lastModifyTs ?? this.lastModifyTs,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  factory GrowthMetric.fromMap(Map<String, dynamic> map) => GrowthMetric(
        uuid: map['uuid'] as String,
        metricTime: DateTime.parse(map['metric_time'] as String),
        height: (map['height'] as num?)?.toDouble() ?? 0,
        weight: (map['weight'] as num?)?.toDouble() ?? 0,
        headCircum: (map['head_circum'] as num?)?.toDouble() ?? 0,
        lastModifyTs: map['last_modify_ts'] as int? ?? 0,
        isDeleted: map['is_deleted'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'uuid': uuid,
        'metric_time': metricTime.toIso8601String(),
        'height': height,
        'weight': weight,
        'head_circum': headCircum,
        'last_modify_ts': lastModifyTs,
        'is_deleted': isDeleted,
      };
}

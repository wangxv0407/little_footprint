/// 成长记录（一条动态）
class GrowthRecord {
  final String uuid;
  final DateTime recordTime; // 事件发生时间（可补录过去）
  final String content; // 文字日记
  final List<String> tags; // 标签
  final String createDevice; // husband / wife
  final int lastModifyTs; // 毫秒时间戳，同步核心
  final int isDeleted; // 0 正常，1 软删除

  const GrowthRecord({
    required this.uuid,
    required this.recordTime,
    required this.content,
    required this.tags,
    required this.createDevice,
    required this.lastModifyTs,
    required this.isDeleted,
  });

  GrowthRecord copyWith({
    String? uuid,
    DateTime? recordTime,
    String? content,
    List<String>? tags,
    String? createDevice,
    int? lastModifyTs,
    int? isDeleted,
  }) =>
      GrowthRecord(
        uuid: uuid ?? this.uuid,
        recordTime: recordTime ?? this.recordTime,
        content: content ?? this.content,
        tags: tags ?? this.tags,
        createDevice: createDevice ?? this.createDevice,
        lastModifyTs: lastModifyTs ?? this.lastModifyTs,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  factory GrowthRecord.fromMap(Map<String, dynamic> map) => GrowthRecord(
        uuid: map['uuid'] as String,
        recordTime: DateTime.parse(map['record_time'] as String),
        content: map['content'] as String? ?? '',
        tags: (map['tags'] as String? ?? '').split(',').where((t) => t.isNotEmpty).toList(),
        createDevice: map['create_device'] as String? ?? 'husband',
        lastModifyTs: map['last_modify_ts'] as int? ?? 0,
        isDeleted: map['is_deleted'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'uuid': uuid,
        'record_time': recordTime.toIso8601String(),
        'content': content,
        'tags': tags.join(','),
        'create_device': createDevice,
        'last_modify_ts': lastModifyTs,
        'is_deleted': isDeleted,
      };
}

import 'record_type.dart';

/// 成长记录（一条动态）
class GrowthRecord {
  final String uuid;

  /// 归属宝宝（v2 起）
  final int babyId;

  /// 事件发生时间（可补录过去）
  final DateTime recordTime;

  /// 文字日记
  final String content;

  /// 标签
  final List<String> tags;

  /// 记录类型，见 [RecordType]
  final String recordType;

  /// 里程碑编码（仅 recordType == milestone 时非空）
  final String milestoneCode;

  /// 0 普通 / 1 收藏
  final int isFavorite;

  /// 记录设备身份：owner / partner（兼容旧值 husband / wife）
  final String createDevice;

  /// 毫秒时间戳，同步核心
  final int lastModifyTs;

  /// 0 正常 / 1 软删除
  final int isDeleted;

  const GrowthRecord({
    required this.uuid,
    this.babyId = 1,
    required this.recordTime,
    this.content = '',
    this.tags = const [],
    this.recordType = RecordType.diary,
    this.milestoneCode = '',
    this.isFavorite = 0,
    this.createDevice = 'owner',
    required this.lastModifyTs,
    this.isDeleted = 0,
  });

  bool get isMilestone => recordType == RecordType.milestone;
  bool get isFavoriteRecord => isFavorite == 1;

  /// 记录人展示名。兼容旧数据的 husband / wife。
  String get authorLabel => switch (createDevice) {
        'wife' || 'partner' => '妈妈',
        'husband' || 'owner' => '爸爸',
        _ => '',
      };

  GrowthRecord copyWith({
    String? uuid,
    int? babyId,
    DateTime? recordTime,
    String? content,
    List<String>? tags,
    String? recordType,
    String? milestoneCode,
    int? isFavorite,
    String? createDevice,
    int? lastModifyTs,
    int? isDeleted,
  }) =>
      GrowthRecord(
        uuid: uuid ?? this.uuid,
        babyId: babyId ?? this.babyId,
        recordTime: recordTime ?? this.recordTime,
        content: content ?? this.content,
        tags: tags ?? this.tags,
        recordType: recordType ?? this.recordType,
        milestoneCode: milestoneCode ?? this.milestoneCode,
        isFavorite: isFavorite ?? this.isFavorite,
        createDevice: createDevice ?? this.createDevice,
        lastModifyTs: lastModifyTs ?? this.lastModifyTs,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  factory GrowthRecord.fromMap(Map<String, dynamic> map) => GrowthRecord(
        uuid: map['uuid'] as String,
        babyId: map['baby_id'] as int? ?? 1,
        recordTime: DateTime.parse(map['record_time'] as String),
        content: map['content'] as String? ?? '',
        tags: (map['tags'] as String? ?? '').split(',').where((t) => t.isNotEmpty).toList(),
        recordType: map['record_type'] as String? ?? RecordType.diary,
        milestoneCode: map['milestone_code'] as String? ?? '',
        isFavorite: map['is_favorite'] as int? ?? 0,
        createDevice: map['create_device'] as String? ?? 'owner',
        lastModifyTs: map['last_modify_ts'] as int? ?? 0,
        isDeleted: map['is_deleted'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'uuid': uuid,
        'baby_id': babyId,
        'record_time': recordTime.toIso8601String(),
        'content': content,
        'tags': tags.join(','),
        'record_type': recordType,
        'milestone_code': milestoneCode,
        'is_favorite': isFavorite,
        'create_device': createDevice,
        'last_modify_ts': lastModifyTs,
        'is_deleted': isDeleted,
      };
}

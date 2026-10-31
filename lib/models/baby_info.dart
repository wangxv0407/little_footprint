/// 宝宝基础信息（v2 起支持多宝宝）
class BabyInfo {
  /// 自增主键；0 表示尚未入库
  final int id;
  final String babyName;
  final DateTime birthDate;

  /// 头像的绝对路径（存放在应用私有目录 avatars/ 下），空串表示无头像
  final String avatarPath;

  /// 0 未知 / 1 男 / 2 女
  final int gender;

  /// 1 表示当前正在查看的宝宝
  final int isActive;

  final int lastModifyTs;

  const BabyInfo({
    this.id = 0,
    required this.babyName,
    required this.birthDate,
    this.avatarPath = '',
    this.gender = 0,
    this.isActive = 1,
    this.lastModifyTs = 0,
  });

  bool get hasAvatar => avatarPath.isNotEmpty;

  String get genderLabel => switch (gender) {
        1 => '男孩',
        2 => '女孩',
        _ => '',
      };

  BabyInfo copyWith({
    int? id,
    String? babyName,
    DateTime? birthDate,
    String? avatarPath,
    int? gender,
    int? isActive,
    int? lastModifyTs,
  }) =>
      BabyInfo(
        id: id ?? this.id,
        babyName: babyName ?? this.babyName,
        birthDate: birthDate ?? this.birthDate,
        avatarPath: avatarPath ?? this.avatarPath,
        gender: gender ?? this.gender,
        isActive: isActive ?? this.isActive,
        lastModifyTs: lastModifyTs ?? this.lastModifyTs,
      );

  factory BabyInfo.fromMap(Map<String, dynamic> map) => BabyInfo(
        id: map['id'] as int? ?? 0,
        babyName: map['baby_name'] as String? ?? '',
        birthDate: DateTime.parse(map['birth_date'] as String),
        avatarPath: map['avatar_path'] as String? ?? '',
        gender: map['gender'] as int? ?? 0,
        isActive: map['is_active'] as int? ?? 1,
        lastModifyTs: map['last_modify_ts'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'baby_name': babyName,
      'birth_date': fmtDate(birthDate),
      'avatar_path': avatarPath,
      'gender': gender,
      'is_active': isActive,
      'last_modify_ts': lastModifyTs,
    };
    if (id > 0) m['id'] = id;
    return m;
  }

  static String fmtDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

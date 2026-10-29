/// 宝宝基础信息（仅一行）
class BabyInfo {
  static const int fixedId = 1;

  final int id;
  final String babyName;
  final DateTime birthDate;
  final String deviceRole; // husband / wife

  const BabyInfo({
    required this.id,
    required this.babyName,
    required this.birthDate,
    required this.deviceRole,
  });

  factory BabyInfo.fromMap(Map<String, dynamic> map) => BabyInfo(
        id: map['id'] as int? ?? fixedId,
        babyName: map['baby_name'] as String? ?? '',
        birthDate: DateTime.parse(map['birth_date'] as String),
        deviceRole: map['device_role'] as String? ?? 'husband',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'baby_name': babyName,
        'birth_date':
            '${birthDate.year.toString().padLeft(4, '0')}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}',
        'device_role': deviceRole,
      };
}

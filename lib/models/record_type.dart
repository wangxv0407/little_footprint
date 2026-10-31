/// 记录类型常量与展示映射
class RecordType {
  /// 日常记录
  static const String diary = 'diary';

  /// 里程碑
  static const String milestone = 'milestone';

  /// 测量（身高体重头围，实际数据在 growth_metric 表，此类型保留给未来合并展示）
  static const String metric = 'metric';

  /// 疫苗
  static const String vaccine = 'vaccine';

  static const List<String> all = [diary, milestone, metric, vaccine];

  static String label(String type) => switch (type) {
        milestone => '里程碑',
        metric => '测量',
        vaccine => '疫苗',
        _ => '日常',
      };
}

/// 计算宝宝月龄 / 天数文案，例如「1岁1月5天」「出生5天」
class AgeCalculator {
  /// 返回完整月龄文案
  static String fullText(DateTime birthDate, DateTime target) {
    if (target.isBefore(birthDate)) return '还未出生';
    final diff = _diff(birthDate, target);
    final years = diff['years']!;
    final months = diff['months']!;
    final days = diff['days']!;
    if (years > 0) {
      return '$years岁${months}月${days}天';
    }
    if (months > 0) {
      return '${months}月${days}天';
    }
    return '出生$days天';
  }

  /// 返回「当前月龄」，用于首页标题展示
  static String titleText(DateTime birthDate, DateTime target) {
    if (target.isBefore(birthDate)) return '出生';
    final diff = _diff(birthDate, target);
    final years = diff['years']!;
    final months = diff['months']!;
    if (years > 0) {
      return '$years岁${months}月';
    }
    if (months > 0) {
      return '${months}个月';
    }
    return '出生${diff['days']!}天';
  }

  static Map<String, int> _diff(DateTime from, DateTime to) {
    int months = (to.year - from.year) * 12 + (to.month - from.month);
    if (to.day < from.day) {
      months--;
    }
    final years = months ~/ 12;
    months = months % 12;
    final days = to.day - from.day;
    final finalDays = days < 0
        ? _daysInPreviousMonth(to.year, to.month) + days
        : days;
    return {'years': years, 'months': months, 'days': finalDays};
  }

  static int _daysInPreviousMonth(int year, int month) {
    if (month == 1) {
      year--;
      month = 12;
    } else {
      month--;
    }
    return DateTime(year, month + 1, 0).day;
  }
}

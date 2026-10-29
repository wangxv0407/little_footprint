/// 时间线分组：今天 / 昨天 / 本周 / 本月 / 更早
class DateGroup {
  final String title;
  final DateTime start; // 组起始（含）
  final DateTime end; // 组结束（含）

  const DateGroup({required this.title, required this.start, required this.end});

  static DateGroup classify(DateTime time, DateTime now) {
    final t = DateTime(time.year, time.month, time.day);
    final today = DateTime(now.year, now.month, now.day);

    if (t == today) {
      return DateGroup(title: '今天', start: today, end: today);
    }
    if (t == today.subtract(const Duration(days: 1))) {
      final y = today.subtract(const Duration(days: 1));
      return DateGroup(title: '昨天', start: y, end: y);
    }
    // 本周（从周一开始）
    final monday = today.subtract(Duration(days: today.weekday - 1));
    if (!t.isBefore(monday) && t.isBefore(today)) {
      return DateGroup(title: '本周', start: monday, end: today.subtract(const Duration(days: 1)));
    }
    // 本月
    final monthStart = DateTime(today.year, today.month, 1);
    if (!t.isBefore(monthStart) && t.isBefore(monday)) {
      return DateGroup(title: '本月', start: monthStart, end: monday.subtract(const Duration(days: 1)));
    }
    return const DateGroup(title: '更早', start: DateTime(1900), end: DateTime(2099));
  }

  /// 把已排序（倒序）的记录列表按时间分组
  static List<DateGroupSection> groupRecords(
      List<DateTime> recordTimes, DateTime now) {
    final sections = <DateGroupSection>[];
    DateGroupSection? current;

    // 记录时间是倒序的，时间大的在前。为正确归组，我们按时间正序扫描再反转。
    final sortedAsc = List<DateTime>.from(recordTimes)
      ..sort((a, b) => a.compareTo(b));
    final ascGroups = <DateGroupSection>[];
    for (final t in sortedAsc) {
      final g = classify(t, now);
      if (current != null && current.title == g.title) {
        current.times.add(t);
      } else {
        current = DateGroupSection(g.title, [t]);
        ascGroups.add(current);
      }
    }
    return ascGroups.reversed.toList();
  }
}

class DateGroupSection {
  final String title;
  final List<DateTime> times;
  DateGroupSection(this.title, this.times);
}

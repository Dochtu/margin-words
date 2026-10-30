/// 日期/时间格式化工具。
///
/// 只依赖 Dart 核心库，避免额外引入 intl 造成版本冲突。
/// 数据库中的 [studyDate] 统一存 `yyyy-MM-dd` 字符串，
/// 这样日期区间筛选可以直接用字符串比较（SQLite 的 BETWEEN）。
class AppDate {
  const AppDate._();

  static const List<String> _weekdays = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// 2026-10-30
  static String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

  static String today() => ymd(DateTime.now());

  /// 10月30日
  static String monthDay(String ymdText) {
    final DateTime? d = parseYmd(ymdText);
    if (d == null) return ymdText;
    return '${d.month}月${d.day}日';
  }

  /// 10月30日 周四
  static String monthDayWeek(DateTime d) =>
      '${d.month}月${d.day}日 ${weekday(d)}';

  static String weekday(DateTime d) => _weekdays[(d.weekday - 1).clamp(0, 6)];

  static String hhmm(int milliseconds) {
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    return '${_two(d.hour)}:${_two(d.minute)}';
  }

  /// 今天 08:12 / 昨天 21:03 / 10月28日 19:40
  static String describeTime(int milliseconds) {
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final DateTime now = DateTime.now();
    final DateTime todayStart = DateTime(now.year, now.month, now.day);
    final DateTime thatDay = DateTime(d.year, d.month, d.day);
    final int diffDays = todayStart.difference(thatDay).inDays;
    if (diffDays == 0) return '今天 ${hhmm(milliseconds)}';
    if (diffDays == 1) return '昨天 ${hhmm(milliseconds)}';
    if (diffDays < 7) return '${diffDays}天前';
    return '${d.month}月${d.day}日';
  }

  static DateTime? parseYmd(String text) {
    final List<String> parts = text.split('-');
    if (parts.length != 3) return null;
    final int? y = int.tryParse(parts[0]);
    final int? m = int.tryParse(parts[1]);
    final int? d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  /// 相对今天的描述，用于空状态文案。
  static String todayLabel() => monthDayWeek(DateTime.now());
}

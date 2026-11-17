import 'model.dart';

bool validRecurrence(Json task) {
  if (![
    'none',
    'daily',
    'weekly',
    'monthly',
    'weekdays',
  ].contains(task['repeatRule'] ?? 'none'))
    return false;
  final every = task['repeatEvery'] ?? 1;
  if (every is! int || every < 1 || every > 365) return false;
  final weekdays = task['repeatWeekdays'];
  if (weekdays != null &&
      (weekdays is! List ||
          weekdays.isEmpty ||
          weekdays.length > 7 ||
          weekdays.any((d) => d is! int || d < 1 || d > 7)))
    return false;
  final day = task['repeatMonthDay'];
  return day == null || day is int && day >= 1 && day <= 31;
}

int _dayDifference(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
DateTime? nextRepeat(Json task, DateTime now) {
  final due = dateOf(task['dueAt']);
  if (due == null || !validRecurrence(task)) return null;
  final rule = task['repeatRule'];
  if (rule == null || rule == 'none') return null;
  final every = task['repeatEvery'] as int? ?? 1;
  final anchor = dateOf(task['repeatAnchor']) ?? due;
  DateTime on(DateTime day) =>
      DateTime(day.year, day.month, day.day, due.hour, due.minute, due.second);
  if (rule == 'monthly') {
    final wanted = task['repeatMonthDay'] as int? ?? anchor.day;
    final reference = now.isAfter(due) ? now : due;
    final delta =
        (reference.year - anchor.year) * 12 + reference.month - anchor.month;
    var index = delta < 0 ? 0 : delta ~/ every;
    for (var i = 0; i < 3; i++, index++) {
      final month = DateTime(anchor.year, anchor.month + index * every, 1);
      final last = DateTime(month.year, month.month + 1, 0).day;
      final candidate = on(
        DateTime(month.year, month.month, wanted.clamp(1, last)),
      );
      if (candidate.isAfter(now) && candidate.isAfter(due)) return candidate;
    }
    return null;
  }
  if (rule == 'weekdays') {
    final selected =
        (task['repeatWeekdays'] as List?)?.cast<int>() ?? [1, 2, 3, 4, 5];
    final start = now.isAfter(due) ? now : due;
    final monday = DateTime(
      anchor.year,
      anchor.month,
      anchor.day - anchor.weekday + 1,
    );
    for (var i = 0; i < every * 7 + 8; i++) {
      final day = DateTime(start.year, start.month, start.day + i),
          candidate = on(day);
      if (selected.contains(day.weekday) &&
          (_dayDifference(monday, day) ~/ 7) % every == 0 &&
          candidate.isAfter(now) &&
          candidate.isAfter(due))
        return candidate;
    }
    return null;
  }
  final days = every * (rule == 'weekly' ? 7 : 1);
  final elapsed = _dayDifference(due, now);
  var steps = elapsed < 0 ? 1 : elapsed ~/ days;
  if (steps < 1) steps = 1;
  var candidate = on(DateTime(due.year, due.month, due.day + steps * days));
  if (!candidate.isAfter(now))
    candidate = on(DateTime(due.year, due.month, due.day + (steps + 1) * days));
  return candidate;
}

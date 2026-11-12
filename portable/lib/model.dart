import 'dart:convert';
import 'package:uuid/uuid.dart';

typedef Json = Map<String, dynamic>;
const uuid = Uuid();
const swiftEpoch = 978307200;
double stamp([DateTime? date]) =>
    (date ?? DateTime.now()).millisecondsSinceEpoch / 1000 - swiftEpoch;
DateTime? dateOf(dynamic value) => value is num
    ? DateTime.fromMillisecondsSinceEpoch(((value + swiftEpoch) * 1000).round())
    : null;
String dayKey(DateTime now) =>
    '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
Json emptyState() => {
  'schemaVersion': 1,
  'tasks': <dynamic>[],
  'routines': <dynamic>[],
  'days': <dynamic>[],
  'notes': <dynamic>[],
  'profile': {'id': uuid.v4().toUpperCase(), 'name': 'My space'},
};
List<Json> rows(Json state, String key) => (state[key] as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();
Json clone(Json state) => jsonDecode(jsonEncode(state)) as Json;

Json decodeTransfer(String text) {
  if (utf8.encode(text).length > 8 * 1024 * 1024)
    throw const FormatException('Backup is too large.');
  final doc = jsonDecode(text);
  if (doc is! Map ||
      doc['format'] != 'OneStep' ||
      doc['formatVersion'] != 1 ||
      doc['state'] is! Map)
    throw const FormatException('Unsupported OneStep backup.');
  final state = Map<String, dynamic>.from(doc['state'] as Map);
  validateState(state);
  return state;
}

void validateState(Json state) {
  if (state['schemaVersion'] != 1)
    throw const FormatException('Unsupported data version.');
  for (final key in ['tasks', 'routines', 'days']) {
    if (state[key] is! List) throw const FormatException('Invalid planner.');
  }
  final xp=rows(state,'xpCompletions');
  if(xp.length>10000 || xp.any((e)=> !Uuid.isValidUUID(fromString:e['accountID']?.toString()??'') || !['task','routine'].contains(e['kind']) || e['eventKey'] is! String || (e['eventKey'] as String).length>90)) {
    throw const FormatException('Invalid XP outbox.');
  }
  for (final key in ['tasks', 'routines']) {
    final items = rows(state, key);
    if (items.length > (key == 'tasks' ? 10000 : 1000) ||
        items.map((e) => e['id']).toSet().length != items.length)
      throw const FormatException('Duplicate or excessive entries.');
    for (final item in items) {
      if (!Uuid.isValidUUID(fromString: item['id']?.toString() ?? '') ||
          item['title'] is! String)
        throw const FormatException('Invalid entry.');
      if (key == 'tasks' &&
          ((item['rewardPoints'] != null &&
                  (item['rewardPoints'] is! int ||
                      item['rewardPoints'] < 0 ||
                      item['rewardPoints'] > 100)) ||
              (item['rewardAccountID'] != null &&
                  !Uuid.isValidUUID(
                    fromString: item['rewardAccountID'].toString(),
                  ))))
        throw const FormatException('Invalid task reward.');
      if (key == 'routines' &&
          (item['hour'] is! int ||
              item['minute'] is! int ||
              item['hour'] < 0 ||
              item['hour'] > 23 ||
              item['minute'] < 0 ||
              item['minute'] > 59))
        throw const FormatException('Invalid routine time.');
    }
  }
}

String encodeTransfer(Json state) => jsonEncode({
  'format': 'OneStep',
  'formatVersion': 1,
  'exportedAt': stamp(),
  'state': state,
});
Json? record(Json state, Json step, DateTime now) {
  for (final r in rows(state, 'days')) {
    if (r['stepID'] == step['id'] && r['day'] == dayKey(now)) return r;
  }
  return null;
}

Json action(Json item, {DateTime? day, Json? state}) => {
  'kind': day == null ? 'task' : 'routine',
  'sourceID': item['id'],
  'title': item['title'],
  'notes': day == null ? item['notes'] ?? '' : 'Daily routine',
  'colorName': item['colorName'],
  if (day != null) 'day': dayKey(day),
  if (day == null && (item['snoozedUntil'] ?? item['dueAt']) != null)
    'scheduledAt': item['snoozedUntil'] ?? item['dueAt'],
  if (day != null)
    'scheduledAt':
        record(state!, item, day)?['snoozedUntil'] ??
        stamp(
          DateTime(
            day.year,
            day.month,
            day.day,
            item['hour'] as int,
            item['minute'] as int,
          ),
        ),
};

List<Json> available(Json state, DateTime now) {
  final time = stamp(now);
  final result = <Json>[];
  for (final t in rows(state, 'tasks')) {
    if (t['completedAt'] == null &&
        t['archived'] != true &&
        (t['snoozedUntil'] == null || t['snoozedUntil'] <= time))
      result.add(action(t));
  }
  final routines = rows(state, 'routines')
    ..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
  for (final step in routines) {
    final r = record(state, step, now);
    if (r?['status'] == null &&
        (r?['snoozedUntil'] == null || r!['snoozedUntil'] <= time))
      result.add(action(step, day: now, state: state));
  }
  return result;
}

Json? nextAction(Json state, DateTime now) {
  final items = available(state, now);
  final focus = state['focusSession']?['action'];
  if (focus != null) {
    for (final item in items) {
      if (item['kind'] == focus['kind'] &&
          item['sourceID'] == focus['sourceID'])
        return item;
    }
  }
  for (final item in items) {
    if (item['scheduledAt'] != null && item['scheduledAt'] <= stamp(now))
      return item;
  }
  for (final item in items) {
    if (item['kind'] == 'task' && item['scheduledAt'] == null) return item;
  }
  items.sort(
    (a, b) => ((a['scheduledAt'] ?? double.infinity) as num).compareTo(
      (b['scheduledAt'] ?? double.infinity) as num,
    ),
  );
  return items.isEmpty ? null : items.first;
}

Json complete(Json original, Json item, {bool skip = false, DateTime? at, String? accountID}) {
  final now = at ?? DateTime.now();
  final state = clone(original);
  if (state['focusSession']?['action']?['sourceID'] == item['sourceID'])
    state.remove('focusSession');
  if (item['kind'] == 'task') {
    final tasks = rows(state, 'tasks');
    final index = tasks.indexWhere((t) => t['id'] == item['sourceID']);
    if (index < 0 || tasks[index]['completedAt'] != null) return state;
    final t = tasks[index];
    t['completedAt'] = stamp(now);
    t.remove('snoozedUntil');
    final rule = t['repeatRule'];
    if ((rule == 'daily' || rule == 'weekly') && t['dueAt'] != null) {
      var due = dateOf(t['dueAt'])!;
      do {
        due = DateTime(
          due.year,
          due.month,
          due.day + (rule == 'daily' ? 1 : 7),
          due.hour,
          due.minute,
        );
      } while (!due.isAfter(now));
      final next = clone(t)
        ..['id'] = uuid.v4().toUpperCase()
        ..['repeatParentID'] = t['id']
        ..['createdAt'] = stamp(now)
        ..['dueAt'] = stamp(due)
        ..remove('completedAt');
      next['microsteps'] = rows(t, 'microsteps')
          .map(
            (s) => {
              'id': uuid.v4().toUpperCase(),
              'title': s['title'],
              'done': false,
            },
          )
          .toList();
      tasks.add(next);
    }
    state['tasks'] = tasks;
  } else {
    if (item['day'] != dayKey(now)) return state;
    final days = rows(state, 'days')
      ..removeWhere(
        (r) => r['stepID'] == item['sourceID'] && r['day'] == dayKey(now),
      );
    days.add({
      'stepID': item['sourceID'],
      'day': dayKey(now),
      'title': item['title'],
      'status': skip ? 'skipped' : 'done',
      'updatedAt': stamp(now),
    });
    state['days'] = days;
  }
  if (!skip && accountID != null && Uuid.isValidUUID(fromString:accountID)) {
    final kind=item['kind'] as String;
    final key=kind + '.' + (item['sourceID'] as String).toLowerCase() + (kind=='routine' ? '.' + item['day'].toString() : '');
    final events=rows(state,'xpCompletions');
    if(events.length<10000 && !events.any((e)=>e['eventKey']==key && e['accountID']==accountID.toLowerCase())) {
      events.add({'eventKey':key,'accountID':accountID.toLowerCase(),'kind':kind});
      state['xpCompletions']=events;
    }
  }
  return state;
}

class AlertPlan {
  final String key, title;
  final DateTime at;
  final bool timer;
  AlertPlan(this.key, this.title, this.at, {this.timer = false});
}

List<AlertPlan> reminders(Json state, DateTime now, {int limit = 60}) {
  final result = <AlertPlan>[];
  final prefs = state['preferences'] as Map? ?? {};
  void add(String key, String title, DateTime date, {bool followup = false}) {
    if (!date.isAfter(now) || (followup && prefs['followup'] == false)) return;
    final start = prefs['quietStart'], end = prefs['quietEnd'];
    if (start is int &&
        end is int &&
        (start < end
            ? date.hour >= start && date.hour < end
            : date.hour >= start || date.hour < end))
      return;
    result.add(AlertPlan(key, title, date));
  }

  for (final t in rows(
    state,
    'tasks',
  ).where((t) => t['completedAt'] == null && t['archived'] != true)) {
    final snooze = dateOf(t['snoozedUntil']);
    final due = dateOf(t['dueAt']);
    if (snooze != null) {
      add('${t['id']}.snooze', t['title'] as String, snooze);
    } else if (t['reminderEnabled'] == true && due != null) {
      add('${t['id']}.due', t['title'] as String, due);
      add(
        '${t['id']}.followup',
        t['title'] as String,
        due.add(const Duration(minutes: 10)),
        followup: true,
      );
    }
  }
  for (var i = 0; i < 14; i++) {
    final day = DateTime(now.year, now.month, now.day + i);
    for (final step in rows(state, 'routines')) {
      final r = record(state, step, day);
      if (r?['status'] != null) continue;
      final snooze = dateOf(r?['snoozedUntil']);
      final due = DateTime(
        day.year,
        day.month,
        day.day,
        step['hour'] as int,
        step['minute'] as int,
      );
      final key = '${step['id']}.${dayKey(day)}';
      if (snooze != null) {
        add('$key.snooze', step['title'] as String, snooze);
      } else {
        add('$key.due', step['title'] as String, due);
        final follow = due.add(const Duration(minutes: 10));
        if (dayKey(follow) == dayKey(day))
          add('$key.followup', step['title'] as String, follow, followup: true);
      }
    }
  }
  final grouped = <int, List<AlertPlan>>{};
  for (final alert in result) {
    grouped.putIfAbsent(alert.at.millisecondsSinceEpoch, () => []).add(alert);
  }
  result.clear();
  for (final group in grouped.values) {
    group.sort((a, b) => a.key.compareTo(b.key));
    result.add(
      group.length == 1
          ? group.first
          : AlertPlan(
              'group.${group.first.at.millisecondsSinceEpoch}',
              '${group.length} steps are ready · ${group.first.title}',
              group.first.at,
            ),
    );
  }
  result.sort((a, b) => a.at.compareTo(b.at));
  final timer = state['focusSession'] as Map?;
  final end = dateOf(timer?['endsAt']);
  final valid =
      timer != null &&
      available(state, now).any(
        (a) =>
            a['sourceID'] == timer['action']['sourceID'] &&
            a['kind'] == timer['action']['kind'],
      );
  final selected = result
      .take(
        valid &&
                end != null &&
                end.isAfter(now) &&
                timer['pausedRemaining'] == null
            ? (limit - 1).clamp(0, limit)
            : limit,
      )
      .toList();
  if (limit > 0 &&
      valid &&
      end != null &&
      end.isAfter(now) &&
      timer['pausedRemaining'] == null)
    selected.add(
      AlertPlan(
        'focus.${timer['id']}',
        timer['action']['title'] as String,
        end,
        timer: true,
      ),
    );
  return selected;
}

Json? nextGuidedRoutine(Json state, DateTime now) {
  final steps = rows(state, 'routines')
    ..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
  for (final step in steps) {
    final r = record(state, step, now);
    if (r?['status'] == null &&
        (dateOf(r?['snoozedUntil'])?.isAfter(now) != true))
      return action(step, day: now, state: state);
  }
  return null;
}

Json undoRoutine(Json original, String id, DateTime now) {
  final state = clone(original);
  if (!rows(state, 'routines').any((s) => s['id'] == id)) return state;
  state['days'] = rows(state, 'days')
    ..removeWhere((r) => r['stepID'] == id && r['day'] == dayKey(now));
  return state;
}

Json rescheduleRoutine(Json original, String id, DateTime date, DateTime now) {
  final state = clone(original);
  if (!date.isAfter(now) || dayKey(date) != dayKey(now))
    throw const FormatException('Choose a future time today.');
  final step = rows(state, 'routines').where((s) => s['id'] == id).firstOrNull;
  if (step == null || record(state, step, now)?['status'] != null)
    throw const FormatException('Choose an incomplete routine step.');
  state['days'] = rows(state, 'days')
    ..removeWhere((r) => r['stepID'] == id && r['day'] == dayKey(now))
    ..add({
      'stepID': id,
      'day': dayKey(now),
      'title': step['title'],
      'snoozedUntil': stamp(date),
      'updatedAt': stamp(now),
    });
  return state;
}

String reminderCoverage(Json state, DateTime now) {
  final plan = reminders(state, now, limit: 100000);
  final limit = plan.length > 60
      ? plan[60].at.subtract(const Duration(seconds: 1))
      : DateTime(now.year, now.month, now.day + 14);
  return plan.length.clamp(0, 60).toString() +
      ' alerts planned; continuous queue coverage through ' +
      dayKey(limit) +
      ' ' +
      limit.hour.toString().padLeft(2, '0') +
      ':' +
      limit.minute.toString().padLeft(2, '0') +
      '. Reopen to refill. Same-time steps share a banner.';
}

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:onestep/model.dart';
import 'package:onestep/content.dart';
import 'package:onestep/connection.dart';

void main() {
  Json catalog() => {
    'format': 'OneStepContent',
    'schema': 1,
    'revision': 1,
    'minAppVersion': '0.5.0',
    'message': 'A small start',
    'packs': [
      {
        'id': 'test-pack',
        'title': 'Morning',
        'description': 'Optional',
        'steps': [
          {'title': 'Water', 'hour': 9, 'minute': 0, 'colorName': 'blue'},
        ],
      },
    ],
  };
  final now = DateTime(2026, 11, 12, 8);
  Json step(String title, int position) => {
    'id': uuid.v4().toUpperCase(),
    'title': title,
    'hour': 9,
    'minute': 0,
    'position': position,
  };
  test('Shipped connection is public-only and pinned to the main service', () {
    expect(Uri.parse(serviceURL).scheme, 'https');
    expect(Uri.parse(serviceURL).host.endsWith('.supabase.co'), isTrue);
    expect(servicePublishableKey.startsWith('sb_publishable_'), isTrue);
  });
  test('Invalid or newer content is rejected', () {
    expect(decodeCatalog(jsonEncode(catalog()))['revision'], 1);
    expect(
      () => decodeCatalog(jsonEncode(catalog()..['schema'] = 2)),
      throwsFormatException,
    );
    expect(
      () => decodeCatalog(jsonEncode(catalog()..['minAppVersion'] = '0.7.0')),
      throwsFormatException,
    );
    final bad = catalog();
    bad['packs'][0]['steps'][0]['hour'] = 25;
    expect(() => decodeCatalog(jsonEncode(bad)), throwsFormatException);
  });
  test('Pack install preserves private edits and is idempotent', () {
    final state = emptyState();
    state['routines'] = [step('My own', 0)];
    final c = catalog(), pack = rows(c, 'packs').first;
    final added = installPack(state, c, pack);
    expect(rows(added, 'routines').length, 2);
    expect(rows(added, 'routines').first['title'], 'My own');
    expect(installPack(added, c, pack), added);
    expect(decodeTransfer(encodeTransfer(added)), added);
  });
  test(
    'Guided sequence advances, honors snooze, and leaves tomorrow fresh',
    () {
      final state = emptyState(), a = step('A', 0), b = step('B', 1);
      state['routines'] = [a, b];
      expect(nextGuidedRoutine(state, now)!['sourceID'], a['id']);
      final done = complete(
        state,
        action(a, day: now, state: state),
        at: now,
      );
      expect(nextGuidedRoutine(done, now)!['sourceID'], b['id']);
      final delayed = rescheduleRoutine(
        done,
        b['id'],
        now.add(const Duration(hours: 2)),
        now,
      );
      expect(nextGuidedRoutine(delayed, now), isNull);
      expect(
        nextGuidedRoutine(
          delayed,
          now.add(const Duration(days: 1)),
        )!['sourceID'],
        a['id'],
      );
    },
  );
  test(
    'Routine undo keeps old history and today-only time keeps templates',
    () {
      final state = emptyState(), s = step('Water', 0);
      state['routines'] = [s];
      state['days'] = [
        {
          'stepID': s['id'],
          'day': '2026-11-11',
          'title': 'Water',
          'status': 'done',
          'updatedAt': stamp(now),
        },
      ];
      final done = complete(
        state,
        action(s, day: now, state: state),
        at: now,
      );
      final undone = undoRoutine(done, s['id'], now);
      expect(rows(undone, 'days').length, 1);
      final moved = rescheduleRoutine(
        undone,
        s['id'],
        now.add(const Duration(hours: 2)),
        now,
      );
      expect(moved['routines'], state['routines']);
      expect(
        () => rescheduleRoutine(
          undone,
          s['id'],
          now.add(const Duration(days: 1)),
          now,
        ),
        throwsFormatException,
      );
    },
  );
  test('Coincident alerts coalesce and disappear on completion', () {
    final state = emptyState(), a = step('A', 0), b = step('B', 1);
    state['routines'] = [a, b];
    final plan = reminders(state, now);
    expect(plan.where((p) => dayKey(p.at) == dayKey(now)).length, 2);
    final done = complete(
      complete(
        state,
        action(a, day: now, state: state),
        at: now,
      ),
      action(b, day: now, state: state),
      at: now,
    );
    expect(
      reminders(done, now).where((p) => dayKey(p.at) == dayKey(now)),
      isEmpty,
    );
  });
}

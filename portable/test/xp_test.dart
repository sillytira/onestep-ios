import 'package:flutter_test/flutter_test.dart';
import 'package:onestep/model.dart';

void main() {
  const user = '66666666-6666-4666-8666-666666666666';
  test(
    'XP completion is account bound and survives a backup; replay is unique',
    () {
      final state = emptyState();
      final task = {
        'id': uuid.v4().toUpperCase(),
        'title': 'Small task',
        'createdAt': stamp(),
      };
      state['tasks'] = [task];
      var done = complete(state, action(task), accountID: user);
      expect(rows(done, 'xpCompletions').single['accountID'], user);
      done = complete(done, action(task), accountID: user);
      expect(rows(done, 'xpCompletions').length, 1);
      expect(
        rows(decodeTransfer(encodeTransfer(done)), 'xpCompletions'),
        rows(done, 'xpCompletions'),
      );
      expect(rows(complete(state, action(task)), 'xpCompletions'), isEmpty);
    },
  );
  test('Skip earns no XP and routine undo/re-complete has one award', () {
    final now = DateTime(2026, 11, 12);
    final state = emptyState();
    final step = {
      'id': uuid.v4(),
      'title': 'Breakfast',
      'hour': 9,
      'minute': 0,
      'position': 0,
    };
    state['routines'] = [step];
    final item = action(step, day: now, state: state);
    expect(
      rows(
        complete(state, item, skip: true, at: now, accountID: user),
        'xpCompletions',
      ),
      isEmpty,
    );
    var done = complete(state, item, at: now, accountID: user);
    done['days'] = [];
    done = complete(done, item, at: now, accountID: user);
    expect(rows(done, 'xpCompletions').length, 1);
  });
}

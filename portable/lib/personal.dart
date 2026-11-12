import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'family.dart';
import 'model.dart';

final personalRewardMessage = ValueNotifier<String>('');
bool _syncingPersonal = false;
Future<void> syncPersonalTasks(Json state) async {
  if (_syncingPersonal) return;
  _syncingPersonal = true;
  try {
    final client = FamilyClient.shared;
    await client.load();
    if (!client.signedIn ||
        client.userID == null ||
        client.accountKind == 'kids')
      return;
    final user = client.userID!, key = 'personal.receipts.$user';
    final saved = await FamilyClient.vault.read(key: key);
    final receipts = saved == null
        ? <String, dynamic>{}
        : jsonDecode(saved) as Json;
    final tasks =
        rows(state, 'tasks')
            .where(
              (t) =>
                  t['rewardPoints'] is int &&
                  (t['rewardAccountID'] as String?)?.toLowerCase() ==
                      user.toLowerCase() &&
                  t['archived'] != true,
            )
            .toList()
          ..sort(
            (a, b) => (b['createdAt'] as num).compareTo(a['createdAt'] as num),
          );
    for (final task in tasks.take(100)) {
      final id = task['id'] as String, points = task['rewardPoints'] as int;
      final receipt = receipts[id] as Map?;
      if (receipt?['done'] == true ||
          (receipt?['retry'] as num? ?? 0) >
              DateTime.now().millisecondsSinceEpoch)
        continue;
      if (points < 0 || points > 100 || (task['title'] as String).length < 3)
        continue;
      final digest = await Sha256().hash(
        utf8.encode('${task['title']}|$points'),
      );
      final hash = digest.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      try {
        if (receipt?['hash'] != hash) {
          await client.rpc('onestep_register_personal_task', {
            'client': id,
            'task_title': task['title'],
            'task_points': points,
          });
          receipts[id] = {'hash': hash};
        }
        if (task['completedAt'] != null) {
          final result =
              await client.rpc('onestep_complete_personal_task', {'client': id})
                  as Map;
          final pending = result['status'] == 'pending';
          (receipts[id] as Map)['done'] = !pending;
          (receipts[id] as Map)['retry'] =
              DateTime.now().millisecondsSinceEpoch + 60000;
          personalRewardMessage.value = pending
              ? 'Done locally. Account points are waiting for the anti-spam check.'
              : 'Last task award: ${result['points']} points · ${result['status']}';
        }
      } catch (e) {
        receipts[id] ??= <String, dynamic>{};
        (receipts[id] as Map)['retry'] =
            DateTime.now().millisecondsSinceEpoch + 60000;
        personalRewardMessage.value =
            'Planner saved. Online rewards will retry while open: $e';
        break;
      }
      await FamilyClient.vault.write(key: key, value: jsonEncode(receipts));
    }
    final keep = tasks.take(100).map((t) => t['id']).toSet();
    receipts.removeWhere((id, _) => !keep.contains(id));
    await FamilyClient.vault.write(key: key, value: jsonEncode(receipts));
  } catch (e) {
    personalRewardMessage.value =
        'Planner works offline. Account rewards are waiting for a connection: $e';
  } finally {
    _syncingPersonal = false;
  }
}

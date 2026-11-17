import 'localization.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'backup_crypto.dart';
import 'family.dart';
import 'model.dart';
import 'planner_merge.dart';
import 'services.dart';

class CloudPlannerSync extends ChangeNotifier {
  final Planner planner;
  final FamilyClient client;
  CloudPlannerSync(this.planner, {FamilyClient? client})
    : client = client ?? FamilyClient.shared;
  Timer? _timer;
  bool busy = false, enabled = false, disposed = false;
  String status = 'Sync is off. Your planner stays on this device.';
  String? _user;
  Json? _base, _localAtConflict;
  PlannerMerge? pending;
  int _revision = 0;
  void changed() {
    if (!disposed) notifyListeners();
  }

  Future<void> start() async {
    _timer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(tick()),
    );
    await tick();
  }

  File baseFile(String user) =>
      File('${planner.directory.path}/sync-$user.encrypted');
  Future<void> enable(String password) async {
    await client.load();
    final user = client.userID;
    if (!client.signedIn || user == null)
      throw const FormatException('Sign in to your own account first.');
    if (password.length < 12 || utf8.encode(password).length > 1024)
      throw const FormatException('Use a passphrase of 12–1,024 characters.');
    final remote = await client.rpc('onestep_sync_read', {}) as Map;
    if (remote['envelope'] != null)
      decodeTransfer(
        await BackupCrypto.open(remote['envelope'] as String, password),
      );
    await FamilyClient.vault.write(key: 'sync.password.$user', value: password);
    await FamilyClient.vault.write(key: 'sync.enabled.$user', value: '1');
    _base = null;
    pending = null;
    await tick();
  }

  Future<void> disable() async {
    await client.load();
    final user = client.userID;
    if (user != null)
      await FamilyClient.vault.write(key: 'sync.enabled.$user', value: '0');
    enabled = false;
    pending = null;
    _base = null;
    status = 'Sync paused. Your encrypted cloud copy is retained.';
    changed();
  }

  Future<void> tick() async {
    if (busy || disposed) return;
    busy = true;
    changed();
    try {
      await client.load();
      final user = client.userID;
      if (_user != user) {
        _user = user;
        _base = null;
        pending = null;
        _localAtConflict = null;
      }
      enabled =
          user != null &&
          client.signedIn &&
          await FamilyClient.vault.read(key: 'sync.enabled.$user') == '1';
      if (!enabled) {
        status = 'Sync is off. Your planner stays on this device.';
        return;
      }
      if (pending != null) {
        status = 'Choose a version for each conflict to continue.';
        return;
      }
      final password = await FamilyClient.vault.read(
        key: 'sync.password.$user',
      );
      if (password == null)
        throw const FormatException('Enter your sync passphrase again.');
      if (_base == null) {
        final file = baseFile(user!);
        if (await file.exists())
          _base = decodeTransfer(
            await BackupCrypto.open(await file.readAsString(), password),
          );
      }
      final local = sharedPlanner(planner.state);
      final response = await client.rpc('onestep_sync_read', {}) as Map;
      if (client.userID != user) return;
      final revision = (response['revision'] as num).toInt();
      final remote = response['envelope'] == null
          ? emptySyncPlanner()
          : decodeTransfer(
              await BackupCrypto.open(response['envelope'] as String, password),
            );
      if (client.userID != user) return;
      final merge = mergePlanner(_base ?? emptySyncPlanner(), local, remote);
      if (merge.conflicts.isNotEmpty) {
        pending = merge;
        _localAtConflict = local;
        _revision = revision;
        status =
            'Concurrent edits need your choice. Neither version was discarded.';
        return;
      }
      if (canonical(merge.state) == canonical(sharedPlanner(remote)) &&
          canonical(merge.state) == canonical(local)) {
        _base = merge.state;
        if (response['envelope'] is String)
          await baseFile(
            user!,
          ).writeAsString(response['envelope'] as String, flush: true);
        status = 'Up to date. Automatic sync runs while OneStep is open.';
        return;
      }
      await publish(merge.state, local, revision, password, user!);
    } catch (e) {
      status = 'Sync paused; your local planner is safe. $e';
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> publish(
    Json merged,
    Json local,
    int revision,
    String password,
    String user,
  ) async {
    final envelope = await BackupCrypto.seal(encodeTransfer(merged), password);
    if (client.userID != user) return;
    final reply =
        await client.rpc('onestep_sync_publish', {
              'expected_revision': revision,
              'payload': envelope,
            })
            as Map;
    if (client.userID != user) return;
    if (reply['status'] != 'saved') {
      status =
          'Another device updated first. No local edits were replaced; retrying on the next sync.';
      return;
    }
    // Apply against the latest queued local write, never an old UI snapshot.
    await planner.transact((current) {
      if (client.userID != user)
        throw const FormatException("The account changed. Sync paused.");
      final rebased = mergePlanner(local, sharedPlanner(current), merged);
      if (rebased.conflicts.isNotEmpty)
        throw const FormatException(
          'New local edits arrived during sync. Refresh to review them.',
        );
      final next = rebased.state;
      if (current['focusSession'] != null)
        next['focusSession'] = current['focusSession'];
      if (current['contentAutoUpdate'] != null)
        next['contentAutoUpdate'] = current['contentAutoUpdate'];
      return next;
    });
    _base = clone(merged);
    await baseFile(user).writeAsString(envelope, flush: true);
    pending = null;
    _localAtConflict = null;
    status = 'Synced securely. Timers stay on their original device.';
  }

  Future<void> resolve(Map<int, bool> choices) async {
    if (busy || pending == null) return;
    final original = _localAtConflict!, merge = pending!, user = _user;
    if (user == null || client.userID != user) return;
    if (canonical(sharedPlanner(planner.state)) != canonical(original)) {
      pending = null;
      status =
          'Your local planner changed. Refresh and review the latest versions.';
      changed();
      return;
    }
    busy = true;
    changed();
    try {
      final password = await FamilyClient.vault.read(
        key: 'sync.password.$user',
      );
      if (password == null) throw const FormatException('Passphrase missing.');
      await publish(
        merge.resolve(choices),
        original,
        _revision,
        password,
        user,
      );
    } catch (e) {
      status = 'Could not finish resolving. No local data was replaced. $e';
    } finally {
      busy = false;
      changed();
    }
  }

  @override
  void dispose() {
    disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

Future<String?> askPassphrase(
  BuildContext context, {
  bool confirm = false,
}) async {
  final password = TextEditingController(), again = TextEditingController();
  String? error;
  final value = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          confirm ? 'Choose a backup passphrase' : 'Enter backup passphrase',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LText(
              'Keep it somewhere safe. A lost passphrase cannot be recovered.',
            ),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const LDecoration(labelText: 'Passphrase'),
            ),
            if (confirm)
              TextField(
                controller: again,
                obscureText: true,
                decoration: const LDecoration(labelText: 'Confirm passphrase'),
              ),
            if (error != null) Text(error!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LText('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (confirm &&
                  (password.text.length < 12 || password.text != again.text)) {
                setState(
                  () => error =
                      'Use at least 12 characters and match both entries.',
                );
                return;
              }
              Navigator.pop(context, password.text);
            },
            child: const LText('Continue'),
          ),
        ],
      ),
    ),
  );
  // Dialog teardown completes before controllers are released.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  password.dispose();
  again.dispose();
  return value;
}

class SyncPage extends StatefulWidget {
  final Planner planner;
  const SyncPage({super.key, required this.planner});
  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final password = TextEditingController();
  final choices = <int, bool>{};
  PlannerMerge? reviewed;
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = widget.planner.cloudSync;
    return Scaffold(
      appBar: AppBar(title: const LText('Private planner sync')),
      body: AnimatedBuilder(
        animation: sync,
        builder: (context, _) {
          if (!identical(reviewed, sync.pending)) {
            reviewed = sync.pending;
            choices.clear();
          }
          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              const LText(
                'Automatic sync, with your permission',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const LText(
                'Uses your signed-in account and an encrypted cloud copy. Use the same passphrase on each device. Your local planner is device-wide: check that it is the data you want in this account before enabling. Back up first.',
              ),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const LDecoration(
                  labelText: 'Sync passphrase (12+ characters)',
                ),
              ),
              FilledButton(
                onPressed: sync.busy
                    ? null
                    : () async {
                        try {
                          await sync.enable(password.text);
                          password.clear();
                        } catch (e) {
                          if (context.mounted)
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      },
                child: const LText('Enable encrypted sync'),
              ),
              Text(sync.status),
              if (sync.busy) const LinearProgressIndicator(),
              Row(
                children: [
                  TextButton(
                    onPressed: sync.busy ? null : sync.tick,
                    child: const LText('Sync now'),
                  ),
                  TextButton(
                    onPressed: sync.busy ? null : sync.disable,
                    child: const LText('Pause sync'),
                  ),
                ],
              ),
              if (sync.pending != null) ...[
                const LText(
                  'Resolve conflicting edits',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                for (var i = 0; i < sync.pending!.conflicts.length; i++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sync.pending!.conflicts[i].label),
                          Text(
                            'This device: ${sync.pending!.conflicts[i].local == null ? 'Deleted' : jsonEncode(sync.pending!.conflicts[i].local)}',
                          ),
                          Text(
                            'Cloud: ${sync.pending!.conflicts[i].remote == null ? 'Deleted' : jsonEncode(sync.pending!.conflicts[i].remote)}',
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: const LText('Use this device'),
                                selected: choices[i] == false,
                                onSelected: (_) =>
                                    setState(() => choices[i] = false),
                              ),
                              ChoiceChip(
                                label: const LText('Use cloud'),
                                selected: choices[i] == true,
                                onSelected: (_) =>
                                    setState(() => choices[i] = true),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed:
                      sync.busy ||
                          choices.length != sync.pending!.conflicts.length
                      ? null
                      : () async {
                          await sync.resolve(choices);
                          if (mounted) setState(choices.clear);
                        },
                  child: const LText('Apply choices'),
                ),
              ],
              const LText(
                'Automatic while open and on resume; mobile operating systems do not guarantee background sync. Offline changes stay local until reconnected. Service migration 007 is required. Your passphrase is stored only in device secure storage, not sent to the service.',
              ),
            ],
          );
        },
      ),
    );
  }
}

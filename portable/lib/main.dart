import 'dart:async';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'model.dart';
import 'services.dart';
import 'family.dart';
import 'content.dart';
import 'personal.dart';
import 'desktop_sidebar.dart';

const appRole = String.fromEnvironment('ONESTEP_ROLE', defaultValue: 'planner');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OneStepApp());
}

const accents = <String, Color>{
  'blue': Color(0xff82aaff),
  'violet': Color(0xffb69bff),
  'mint': Color(0xff6bdfbd),
  'coral': Color(0xffffa080),
  'rose': Color(0xffff94bc),
  'amber': Color(0xffffd079),
};
Color accent(Json item) => accents[item['colorName']] ?? accents['blue']!;
String clock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

class OneStepApp extends StatelessWidget {
  const OneStepApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'OneStep',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accents['blue']!,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xff090a0c),
      cardTheme: const CardThemeData(
        color: Color(0xff1c1d21),
        elevation: 0,
        margin: EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
        ),
      ),
      dividerTheme: const DividerThemeData(color:Color(0xff2a2c37),thickness:1),
      appBarTheme: const AppBarTheme(backgroundColor:Color(0xff0e1016),surfaceTintColor:Colors.transparent,centerTitle:false),
      navigationBarTheme:const NavigationBarThemeData(backgroundColor:Color(0xff14161e),indicatorColor:Color(0xff37314f)),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 50)),
      ),
    ),
    home: appRole == 'planner'
        ? const Home()
        : const RewardsPage(role: appRole),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  Planner? planner;
  String? fatal;
  int tab = 0;
  bool busy = false;
  String search = '';
  bool archived = false;
  Json? guided;
  String? guidedDay;
  Timer? ticker;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      if (DateTime.now().second == 0 && planner != null)
        unawaited(syncPersonalTasks(planner!.state));
    });
  }

  Future<void> load() async {
    try {
      final loaded = await Planner.load();
      if (!mounted) return;
      setState(() {
        planner = loaded;
        fatal = null;
      });
      loaded.addListener(changed);
      if (loaded.state['contentAutoUpdate'] != false) {
        unawaited(ContentCache(loaded.directory).refreshQuietly());
      }
    } catch (e) {
      if (mounted)
        setState(() {
          fatal =
              'Your saved planner could not be opened. Nothing was reset. $e';
        });
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ticker?.cancel();
    planner?.removeListener(changed);
    planner?.alerts.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && planner != null)
      planner!.alerts.apply(planner!.state).catchError((Object e) {
        planner!.warning = '$e';
      });
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
    });
    try {
      await action();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted)
        setState(() {
          busy = false;
        });
    }
  }

  Future<void> edit({
    Json? item,
    bool routine = false,
    bool note = false,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntryEditor(
          planner: planner!,
          item: item,
          routine: routine,
          note: note,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (planner == null)
      return Scaffold(
        body: Center(
          child: fatal == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(fatal!),
                      TextButton(onPressed: load, child: const Text('Retry')),
                    ],
                  ),
                ),
        ),
      );
    final p = planner!;
    final state = p.state;
    final now = DateTime.now();
    final names = ['Now', 'Tasks', 'Routines', 'Notes', 'History'];
    final icons = [
      Icons.auto_awesome_outlined,
      Icons.checklist_rounded,
      Icons.wb_twilight,
      Icons.notes_rounded,
      Icons.history_rounded,
    ];
    final wide = MediaQuery.sizeOf(context).width > 800;
    return Scaffold(
      appBar: AppBar(
        title: Text(names[tab]),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(tooltip:'OneStep Bank',icon:const Icon(Icons.account_balance_wallet_outlined),onPressed:(){Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const RewardsPage(role:'bank')));}),
          IconButton(
            tooltip: 'Data, devices, and settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsPage(planner: p),
                ),
              );
            },
          ),
        ],
      ),
      body: Row(
        children: [
          if (wide) DesktopSidebar(
            selected:tab,names:names,icons:icons,expanded:MediaQuery.sizeOf(context).width>=1100,
            onSelect:(i)=>setState(()=>tab=i),onAdd:()=>edit(),
            onBank:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const RewardsPage(role:'bank'))),
            onSettings:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>SettingsPage(planner:p))),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  children: [
                    if (p.warning != null)
                      MaterialBanner(
                        content: Text(p.warning!),
                        actions: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                p.warning = null;
                              });
                            },
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    Expanded(
                      child: switch (tab) {
                        0 => nowPage(state, now),
                        1 => tasksPage(state),
                        2 => routinesPage(state, now),
                        3 => notesPage(state),
                        _ => historyPage(state),
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (v) => setState(() {
                tab = v;
              }),
              destinations: List.generate(
                names.length,
                (i) => NavigationDestination(
                  icon: Icon(icons[i]),
                  label: names[i],
                ),
              ),
            ),
      floatingActionButton: tab == 1 || tab == 2 || tab == 3
          ? FloatingActionButton(
              tooltip: tab == 2
                  ? 'Add routine step'
                  : tab == 3
                  ? 'Add note'
                  : 'Add task',
              onPressed: () {
                edit(routine: tab == 2, note: tab == 3);
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget box(List<Widget> children, {Color? color}) => Card(
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: color == null
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                colors: [color.withValues(alpha: .19), const Color(0xff1c1d21)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );
  Widget nowPage(Json state, DateTime now) {
    final p = planner!;
    if (guided != null &&
        !available(state, now).any(
          (a) =>
              a['kind'] == guided!['kind'] &&
              a['sourceID'] == guided!['sourceID'],
        ))
      guided = null;
    if (guidedDay != dayKey(now)) {
      guided = null;
      guidedDay = null;
    }
    if (guidedDay != null) {
      guided = nextGuidedRoutine(state, now);
      if (guided == null) guidedDay = null;
    }
    final item = guided ?? nextAction(state, now);
    final session = state['focusSession'] as Map?;
    final count =
        rows(state, 'tasks').where((t) => t['completedAt'] != null).length +
        rows(state, 'days').where((r) => r['status'] == 'done').length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(MaterialLocalizations.of(context).formatFullDate(now), style: TextStyle(color: accents['amber'])),
        const SizedBox(height: 12),
        const Text(
          'One thing at a time.',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (item != null)
          box([
            Row(
              children: [
                Icon(
                  item['kind'] == 'routine'
                      ? Icons.wb_twilight
                      : Icons.checklist,
                  color: accent(item),
                ),
                const SizedBox(width: 12),
                Text(
                  item['kind'] == 'routine'
                      ? 'DAILY ROUTINE'
                      : 'YOUR NEXT STEP',
                  style: TextStyle(color: accent(item), letterSpacing: 1.4),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              item['title'] as String,
              style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w700),
            ),
            if ((item['notes'] as String? ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  item['notes'] as String,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            if (dateOf(item['scheduledAt']) case final DateTime date)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '${date.isBefore(now) ? 'Ready when you are' : 'Coming up'} · ${clock(date)}',
                  style: const TextStyle(color: Colors.white60),
                ),
              ),
            const SizedBox(height: 18),
            if (session != null &&
                session['action']['sourceID'] == item['sourceID']) ...[
              Text(
                session['pausedRemaining'] != null
                    ? 'Paused · ${Duration(seconds: (session['pausedRemaining'] as num).round()).toString().split('.').first}'
                    : 'Focus · ${Duration(seconds: (dateOf(session['endsAt'])!.difference(now).inSeconds).clamp(0, 28800)).toString().split('.').first}',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Wrap(
                spacing: 12,
                children: [
                  if (session['durationBased'] == true)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              run(() async {
                                final next = clone(p.state);
                                final t = next['focusSession'] as Map;
                                if (t['pausedRemaining'] != null) {
                                  t['startedAt'] = stamp();
                                  t['endsAt'] =
                                      stamp() + (t['pausedRemaining'] as num);
                                  t.remove('pausedRemaining');
                                } else {
                                  final remaining =
                                      (t['endsAt'] as num) - stamp();
                                  if (remaining <= 0) return;
                                  t['pausedRemaining'] = remaining;
                                }
                                await p.save(next);
                              });
                            },
                      child: Text(
                        session['pausedRemaining'] == null
                            ? 'Pause timer'
                            : 'Resume timer',
                      ),
                    ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () {
                            run(
                              () => p.save(
                                clone(p.state)..remove('focusSession'),
                              ),
                            );
                          },
                    child: const Text('Stop timer'),
                  ),
                ],
              ),
            ] else
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        focus(item);
                      },
                icon: const Icon(Icons.timer_outlined),
                label: const Text('Start a timer'),
              ),
            ...smallSteps(state, item),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: accents['mint'],
                  foregroundColor: Colors.black,
                ),
                onPressed: busy
                    ? null
                    : () {
                        run(() async {
                          await p.save(complete(p.state, item));
                          guided = guidedDay == dayKey(DateTime.now())
                              ? nextGuidedRoutine(p.state, DateTime.now())
                              : null;
                          if (guided == null) guidedDay = null;
                        });
                      },
                icon: const Icon(Icons.check),
                label: const Text('Done'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: busy
                    ? null
                    : () {
                        run(() => p.snooze(item));
                      },
                child: Text(
                  'Snooze ${state['preferences']?['snoozeMinutes'] ?? 10} minutes',
                ),
              ),
            ),
            if (item['kind'] == 'routine')
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        run(() => p.save(complete(p.state, item, skip: true)));
                      },
                child: const Text('Skip today'),
              ),
          ], color: accent(item))
        else
          box([
            const Icon(Icons.spa_outlined, size: 36),
            const SizedBox(height: 12),
            const Text(
              'A little breathing room',
              style: TextStyle(fontSize: 24),
            ),
            const Text(
              'Nothing needs your attention right now. Snoozed steps return when ready.',
            ),
          ]),
        box([
          const Icon(Icons.style_outlined, size: 32),
          const SizedBox(height: 18),
          Text(
            '$count',
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
          ),
          if (guidedDay != null)
            TextButton(
              onPressed: () => setState(() {
                guidedDay = null;
                guided = null;
              }),
              child: const Text('Leave guided routine'),
            ),
          const Text('Steps finished', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          const Text(
            'Your progress, without a streak to maintain. This private step count is not spendable points. Bank shows your parent-approved family rewards.',
            style: TextStyle(color: Colors.white60),
          ),
        ], color: accents['violet']),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () {
            edit();
          },
          icon: const Icon(Icons.add),
          label: const Text('Capture a thought'),
        ),
      ],
    );
  }

  List<Widget> smallSteps(Json state, Json item) {
    if (item['kind'] != 'task') return [];
    final tasks = rows(
      state,
      'tasks',
    ).where((t) => t['id'] == item['sourceID']);
    if (tasks.isEmpty) return [];
    return rows(tasks.first, 'microsteps')
        .map(
          (step) => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(step['title'] as String),
            value: step['done'] == true,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: busy
                ? null
                : (value) {
                    run(() async {
                      final next = clone(planner!.state);
                      for (final t in next['tasks'] as List) {
                        if (t['id'] == item['sourceID']) {
                          for (final s in t['microsteps'] as List) {
                            if (s['id'] == step['id']) s['done'] = value;
                          }
                        }
                      }
                      await planner!.save(next);
                    });
                  },
          ),
        )
        .toList();
  }

  Future<void> focus(Json item) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('A little focus time'),
        children: [
          for (final minutes in [5, 10, 15, 25, 45, 60])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, minutes),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text('$minutes minutes'),
              ),
            ),
        ],
      ),
    );
    if (selected == null) return;
    if (planner!.state['focusSession'] != null && mounted) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Replace current timer?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep current'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (replace != true) return;
    }
    await run(() async {
      final now = DateTime.now();
      final next = clone(planner!.state)
        ..['focusSession'] = {
          'id': uuid.v4().toUpperCase(),
          'action': item,
          'startedAt': stamp(now),
          'endsAt': stamp(now.add(Duration(minutes: selected))),
          'durationBased': true,
        };
      await planner!.save(next);
    });
  }

  Widget tasksPage(Json state) {
    final tasks =
        rows(state, 'tasks')
            .where(
              (t) =>
                  t['completedAt'] == null &&
                  (t['archived'] == true) == archived &&
                  '${t['title']} ${t['notes']} ${t['listName']}'
                      .toLowerCase()
                      .contains(search.toLowerCase()),
            )
            .toList()
          ..sort(
            (a, b) => (a['pinned'] == true ? 0 : 1).compareTo(
              b['pinned'] == true ? 0 : 1,
            ),
          );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search tasks, notes, and lists',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (s) => setState(() {
            search = s;
          }),
        ),
        SwitchListTile(
          title: const Text('Show archived'),
          value: archived,
          onChanged: (v) => setState(() {
            archived = v;
          }),
        ),
        if (tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Text('Room for a fresh start. Tap + to add a task.'),
          ),
        for (final t in tasks)
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(18),
              leading: Icon(
                t['pinned'] == true ? Icons.push_pin : Icons.checklist,
                color: accent(t),
              ),
              title: Text(t['title'] as String),
              subtitle: Text(
                [
                  if (dateOf(t['dueAt']) case final DateTime d)
                    '${dayKey(d)} · ${clock(d)}',
                  if ((t['listName'] as String? ?? '').isNotEmpty)
                    t['listName'] as String,
                ].join('\n'),
              ),
              onTap: () {
                edit(item: t);
              },
              trailing: PopupMenuButton<String>(
                onSelected: (choice) {
                  run(() async {
                    final next = clone(planner!.state);
                    if (choice == 'done') {
                      await planner!.save(complete(next, action(t)));
                      return;
                    }
                    final tasks = rows(next, 'tasks');
                    if (choice == 'delete') {
                      tasks.removeWhere((v) => v['id'] == t['id']);
                    } else {
                      final item = tasks.firstWhere((v) => v['id'] == t['id']);
                      final key = choice == 'pin' ? 'pinned' : 'archived';
                      item[key] = item[key] != true;
                    }
                    next['tasks'] = tasks;
                    if (next['focusSession']?['action']?['sourceID'] == t['id'])
                      next.remove('focusSession');
                    await planner!.save(next);
                  });
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'done', child: Text('Done')),
                  PopupMenuItem(
                    value: 'pin',
                    child: Text(t['pinned'] == true ? 'Unpin' : 'Pin'),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(archived ? 'Unarchive' : 'Archive'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> todayTime(Json step) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        DateTime.now().add(const Duration(minutes: 10)),
      ),
    );
    if (picked == null || !mounted) return;
    final now = DateTime.now();
    await run(
      () => planner!.save(
        rescheduleRoutine(
          planner!.state,
          step['id'] as String,
          DateTime(now.year, now.month, now.day, picked.hour, picked.minute),
          now,
        ),
      ),
    );
  }

  Widget routinesPage(Json state, DateTime now) {
    final routines = rows(state, 'routines')
      ..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
      children: [
        const Text(
          'The same gentle structure, every day. Done and Skip only affect today.',
        ),
        TextButton.icon(
          onPressed: () {
            final pending = routines.where(
              (s) => record(state, s, now)?['status'] == null,
            );
            if (pending.isNotEmpty)
              setState(() {
                guidedDay = dayKey(now);
                guided = nextGuidedRoutine(state, now);
                tab = 0;
              });
          },
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start a guided routine'),
        ),
        for (final step in routines)
          box([
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.wb_twilight, color: accent(step)),
              title: Text(step['title'] as String),
              subtitle: Text(
                '${(step['hour'] as int).toString().padLeft(2, '0')}:${(step['minute'] as int).toString().padLeft(2, '0')} · ${record(state, step, now)?['status'] ?? 'Ready today'}',
              ),
              onTap: () {
                edit(item: step, routine: true);
              },
              trailing: IconButton(
                tooltip: 'Delete step',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  run(() async {
                    final next = clone(planner!.state);
                    (next['routines'] as List).removeWhere(
                      (s) => s['id'] == step['id'],
                    );
                    if (next['focusSession']?['action']?['sourceID'] ==
                        step['id'])
                      next.remove('focusSession');
                    await planner!.save(next);
                  });
                },
              ),
            ),
            if (record(state, step, now)?['status'] != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        run(
                          () => planner!.save(
                            undoRoutine(
                              planner!.state,
                              step['id'] as String,
                              DateTime.now(),
                            ),
                          ),
                        );
                      },
                child: const Text('Undo today'),
              ),
            if (record(state, step, now)?['status'] == null)
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        todayTime(step);
                      },
                child: const Text('Change today’s time'),
              ),
            if (record(state, step, now)?['status'] == null)
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () {
                            run(
                              () => planner!.save(
                                complete(
                                  planner!.state,
                                  action(step, day: now, state: state),
                                ),
                              ),
                            );
                          },
                    child: const Text('Done'),
                  ),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () {
                            run(
                              () => planner!.snooze(
                                action(step, day: now, state: state),
                              ),
                            );
                          },
                    child: const Text('Snooze'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () {
                            run(
                              () => planner!.save(
                                complete(
                                  planner!.state,
                                  action(step, day: now, state: state),
                                  skip: true,
                                ),
                              ),
                            );
                          },
                    child: const Text('Skip today'),
                  ),
                ],
              ),
          ], color: accent(step)),
      ],
    );
  }

  Widget notesPage(Json state) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
    children: [
      for (final note in rows(state, 'notes'))
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(20),
            leading: Icon(Icons.notes, color: accents['rose']),
            title: Text(note['title'] as String),
            subtitle: Text(
              note['body'] as String,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              edit(item: note, note: true);
            },
            trailing: IconButton(
              tooltip: 'Delete note',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                run(() async {
                  final next = clone(planner!.state);
                  (next['notes'] as List).removeWhere(
                    (n) => n['id'] == note['id'],
                  );
                  await planner!.save(next);
                });
              },
            ),
          ),
        ),
    ],
  );
  Widget historyPage(Json state) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Completed tasks',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      for (final t in rows(
        state,
        'tasks',
      ).where((t) => t['completedAt'] != null))
        Card(
          child: ListTile(
            title: Text(t['title'] as String),
            subtitle: Text(dayKey(dateOf(t['completedAt'])!)),
            trailing: TextButton(
              onPressed: () {
                run(() async {
                  final next = clone(planner!.state);
                  final tasks = rows(next, 'tasks');
                  tasks.removeWhere(
                    (v) =>
                        v['repeatParentID'] == t['id'] &&
                        v['completedAt'] == null,
                  );
                  tasks
                      .firstWhere((v) => v['id'] == t['id'])
                      .remove('completedAt');
                  next['tasks'] = tasks;
                  await planner!.save(next);
                });
              },
              child: const Text('Undo'),
            ),
          ),
        ),
      const SizedBox(height: 20),
      const Text(
        'Routine history',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      for (final r in rows(
        state,
        'days',
      ).where((r) => r['status'] != null).toList().reversed)
        Card(
          child: ListTile(
            leading: Icon(
              r['status'] == 'done'
                  ? Icons.check_circle_outline
                  : Icons.skip_next,
            ),
            title: Text(r['title'] as String),
            subtitle: Text('${r['day']} · ${r['status']}'),
            trailing: r['day'] == dayKey(DateTime.now())
                ? TextButton(
                    onPressed: () {
                      run(
                        () => planner!.save(
                          undoRoutine(
                            planner!.state,
                            r['stepID'] as String,
                            DateTime.now(),
                          ),
                        ),
                      );
                    },
                    child: const Text('Undo today'),
                  )
                : null,
          ),
        ),
    ],
  );
}

class EntryEditor extends StatefulWidget {
  final Planner planner;
  final Json? item;
  final bool routine, note;
  const EntryEditor({
    super.key,
    required this.planner,
    this.item,
    this.routine = false,
    this.note = false,
  });
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  late final TextEditingController title, notes, steps, list;
  late String color, repeat;
  late DateTime due;
  late bool hasDate, remind;
  bool busy = false;
  String? error;
  final rewardAccount = FamilyClient.shared;
  bool rewardEnabled = false;
  int rewardPoints = 10;
  @override
  void initState() {
    super.initState();
    final t = widget.item;
    rewardEnabled = widget.item?['rewardPoints'] != null;
    rewardPoints = widget.item?['rewardPoints'] as int? ?? 10;
    rewardAccount.load().then((_) {
      if (mounted) setState(() {});
    });
    title = TextEditingController(text: t?['title'] as String? ?? '');
    notes = TextEditingController(
      text: t?[widget.note ? 'body' : 'notes'] as String? ?? '',
    );
    steps = TextEditingController(
      text: t == null
          ? ''
          : rows(t, 'microsteps').map((s) => s['title']).join('\n'),
    );
    list = TextEditingController(text: t?['listName'] as String? ?? '');
    color = t?['colorName'] as String? ?? (widget.routine ? 'violet' : 'blue');
    repeat = t?['repeatRule'] as String? ?? 'none';
    due = widget.routine
        ? DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
            t?['hour'] as int? ?? 9,
            t?['minute'] as int? ?? 0,
          )
        : dateOf(t?['dueAt']) ?? DateTime.now().add(const Duration(hours: 1));
    hasDate = t?['dueAt'] != null;
    remind = t?['reminderEnabled'] as bool? ?? true;
  }

  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    steps.dispose();
    list.dispose();
    super.dispose();
  }

  Future<void> chooseDate() async {
    if (!widget.routine) {
      final date = await showDatePicker(
        context: context,
        initialDate: due,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (date == null || !mounted) return;
      due = DateTime(date.year, date.month, date.day, due.hour, due.minute);
    }
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(due),
    );
    if (time != null)
      setState(() {
        due = DateTime(due.year, due.month, due.day, time.hour, time.minute);
      });
  }

  Future<void> save() async {
    if (title.text.trim().isEmpty || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next = clone(widget.planner.state);
      final key = widget.note
          ? 'notes'
          : widget.routine
          ? 'routines'
          : 'tasks';
      final items = rows(next, key);
      final t = widget.item == null
          ? <String, dynamic>{'id': uuid.v4().toUpperCase()}
          : clone(widget.item!);
      t['title'] = title.text.trim();
      if (!widget.note && !widget.routine && t['completedAt'] == null) {
        if (rewardEnabled &&
            rewardAccount.signedIn &&
            rewardAccount.accountKind != 'kids') {
          t['rewardPoints'] = rewardPoints;
          t['rewardAccountID'] = t['rewardAccountID'] ?? rewardAccount.userID;
        } else {
          t.remove('rewardPoints');
          t.remove('rewardAccountID');
        }
      }
      if (widget.note) {
        t['body'] = notes.text;
        t['updatedAt'] = stamp();
      } else {
        t['colorName'] = color;
        if (widget.routine) {
          t['hour'] = due.hour;
          t['minute'] = due.minute;
          t['position'] ??= items.length;
        } else {
          t['notes'] = notes.text;
          t['createdAt'] ??= stamp();
          t['reminderEnabled'] = hasDate && remind;
          t.remove('snoozedUntil');
          if (hasDate) {
            t['dueAt'] = stamp(due);
          } else {
            t.remove('dueAt');
          }
          if (hasDate && repeat != 'none') {
            t['repeatRule'] = repeat;
          } else {
            t.remove('repeatRule');
          }
          t['listName'] = list.text;
          final old = rows(t, 'microsteps');
          t['microsteps'] = steps.text
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .map(
                (s) =>
                    old.where((v) => v['title'] == s).firstOrNull ??
                    {'id': uuid.v4().toUpperCase(), 'title': s, 'done': false},
              )
              .toList();
        }
      }
      final index = items.indexWhere((v) => v['id'] == t['id']);
      if (index < 0) {
        items.add(t);
      } else {
        items[index] = t;
      }
      next[key] = items;
      await widget.planner.save(next);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(() {
          error = '$e';
        });
    } finally {
      if (mounted)
        setState(() {
          busy = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.note
            ? 'Keep a thought'
            : widget.routine
            ? 'Daily step'
            : 'Capture a thought',
      ),
      actions: [
        TextButton(onPressed: busy ? null : save, child: const Text('Save')),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (!widget.note &&
                !widget.routine &&
                rewardAccount.signedIn &&
                rewardAccount.accountKind != 'kids') ...[
              SwitchListTile(
                title: const Text('Enroll this task for account rewards'),
                value: rewardEnabled,
                onChanged: widget.item?['completedAt'] != null
                    ? null
                    : (v) => setState(() => rewardEnabled = v),
              ),
              if (rewardEnabled)
                DropdownButtonFormField<int>(
                  initialValue: rewardPoints,
                  decoration: const InputDecoration(
                    labelText: 'Points for this task',
                  ),
                  items: [
                    for (var i = 0; i <= 100; i++)
                      DropdownMenuItem(value: i, child: Text('$i')),
                  ],
                  onChanged: widget.item?['completedAt'] != null
                      ? null
                      : (v) => setState(() => rewardPoints = v ?? 10),
                ),
              const Text(
                'Self-reported: up to20 counted tasks and500 earned points per UTC day. The title is sent for duplicate checks; only a hash is stored. Done remains immediate/offline. Points wait for the server.',
              ),
            ],

            TextField(
              controller: title,
              decoration: const InputDecoration(
                labelText: 'One thing to remember',
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: null,
            ),
            const SizedBox(height: 18),
            if (!widget.routine)
              TextField(
                controller: notes,
                decoration: InputDecoration(
                  labelText: widget.note ? 'Note' : 'A little context',
                ),
                minLines: 3,
                maxLines: 10,
              ),
            if (!widget.note) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: accents.entries
                    .map(
                      (e) => ChoiceChip(
                        label: Text(e.key),
                        selected: color == e.key,
                        selectedColor: e.value.withValues(alpha: .35),
                        onSelected: (_) => setState(() {
                          color = e.key;
                        }),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 18),
              if (widget.routine)
                OutlinedButton(
                  onPressed: chooseDate,
                  child: Text('Every day at ${clock(due)}'),
                )
              else ...[
                SwitchListTile(
                  title: const Text('Set a due time'),
                  value: hasDate,
                  onChanged: (v) => setState(() {
                    hasDate = v;
                  }),
                ),
                if (hasDate) ...[
                  OutlinedButton(
                    onPressed: chooseDate,
                    child: Text('${dayKey(due)} · ${clock(due)}'),
                  ),
                  SwitchListTile(
                    title: const Text('Remind me'),
                    value: remind,
                    onChanged: (v) => setState(() {
                      remind = v;
                    }),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: repeat,
                    decoration: const InputDecoration(
                      labelText: 'Repeat after completion',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('Never')),
                      DropdownMenuItem(value: 'daily', child: Text('Daily')),
                      DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    ],
                    onChanged: (v) => setState(() {
                      repeat = v ?? 'none';
                    }),
                  ),
                ],
                const SizedBox(height: 18),
                TextField(
                  controller: steps,
                  decoration: const InputDecoration(
                    labelText: 'Small steps · one per line',
                  ),
                  minLines: 3,
                  maxLines: 8,
                ),
                TextButton(
                  onPressed: () {
                    if (steps.text.isEmpty)
                      steps.text =
                          'Get what I need\nDo just the first two minutes\nChoose the next small step';
                  },
                  child: const Text('Make it smaller'),
                ),
                TextField(
                  controller: list,
                  decoration: const InputDecoration(
                    labelText: 'List name (optional)',
                  ),
                ),
              ],
            ],
            if (error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    ),
  );
}

class SettingsPage extends StatefulWidget {
  final Planner planner;
  const SettingsPage({super.key, required this.planner});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  final lan = LanTransfer();
  final name = TextEditingController(),
      host = TextEditingController(),
      code = TextEditingController(),
      project = TextEditingController(),
      key = TextEditingController(),
      email = TextEditingController(),
      otp = TextEditingController();
  String message = '', invitation = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    name.text =
        widget.planner.state['profile']?['name'] as String? ?? 'My space';
    LanTransfer.addresses().then((v) {
      if (mounted && v.isNotEmpty)
        setState(() {
          host.text = v.first;
        });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    lan.stop();
    for (final c in [name, host, code, project, key, email, otp]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      lan.stop();
      if (mounted)
        setState(() {
          invitation = '';
        });
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await action();
    } catch (e) {
      if (mounted)
        setState(() {
          message = '$e';
        });
    } finally {
      if (mounted)
        setState(() {
          busy = false;
        });
    }
  }

  Future<void> preview(Json incoming) async {
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Replace this device’s planner?'),
        content: Text(
          '${incoming['profile']?['name'] ?? 'Unnamed space'}\n${rows(incoming, 'tasks').length} tasks · ${rows(incoming, 'routines').length} routine steps · ${rows(incoming, 'days').length} history records · ${rows(incoming, 'notes').length} notes\n\nA recovery copy is saved before replacement. Export both devices first if they have different edits. Active timers are not transferred.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Import snapshot'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await widget.planner.replace(incoming);
      if (mounted)
        setState(() {
          name.text = incoming['profile']?['name'] as String? ?? 'My space';
          message = 'Imported. Previous planner saved in recovery backups.';
        });
    }
  }

  Future<void> export() async {
    final text = encodeTransfer(widget.planner.state);
    if (Platform.isAndroid) {
      await const MethodChannel(
        'meow.tira.onestep/files',
      ).invokeMethod<void>('exportBackup', text);
    } else {
      final location = await getSaveLocation(
        suggestedName: 'OneStep-backup.json',
      );
      if (location != null)
        await File(location.path).writeAsString(text, flush: true);
    }
    if (mounted)
      setState(() {
        message = 'Backup export finished.';
      });
  }

  Widget section(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...children.expand((w) => [w, const SizedBox(height: 14)]),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final p = widget.planner;
    final prefs = p.state['preferences'] as Map? ?? {};
    return Scaffold(
      appBar: AppBar(title: const Text('Your space')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              section('Content updates', [
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ContentPage(planner: p),
                      ),
                    );
                  },
                  icon: const Icon(Icons.system_update_alt),
                  label: const Text('Content updates and routine packs'),
                ),
                const Text(
                  'Refresh routine packs inside the installed app. Native code changes still require an app update.',
                ),
              ]),
              section('Rewards and family', [
                for (final role in ['bank', 'kids', 'parent'])
                  OutlinedButton.icon(
                    icon: Icon(
                      role == 'bank'
                          ? Icons.credit_card
                          : role == 'kids'
                          ? Icons.child_care
                          : Icons.family_restroom,
                    ),
                    label: Text(
                      role == 'bank'
                          ? 'Bank and rewards'
                          : role == 'kids'
                          ? 'Kids account'
                          : 'Parent controls',
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RewardsPage(role: role),
                        ),
                      );
                    },
                  ),
                const Text(
                  'Optional services. Your offline planner continues to work without signing in.',
                ),
              ]),
              section('Profile', [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () {
                          run(() async {
                            final next = clone(p.state);
                            next['profile'] ??= {'id': uuid.v4().toUpperCase()};
                            next['profile']['name'] = name.text.trim();
                            if (name.text.trim().isEmpty) return;
                            await p.save(next);
                            setState(() {
                              message = 'Local profile saved.';
                            });
                          });
                        },
                  child: const Text('Save local profile'),
                ),
                const Text(
                  'Works offline. Pairing copies a profile; it does not verify online account ownership.',
                ),
              ]),
              section('Reminders', [
                Text(reminderCoverage(p.state, DateTime.now())),
                if (Platform.isAndroid)
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () {
                            run(p.alerts.permissions);
                          },
                    child: const Text(
                      'Enable notifications and precise alarms',
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('One follow-up after 10 minutes'),
                  value: prefs['followup'] != false,
                  onChanged: busy
                      ? null
                      : (v) {
                          run(() async {
                            final next = clone(p.state);
                            next['preferences'] ??= {
                              'snoozeMinutes': 10,
                              'followup': true,
                            };
                            next['preferences']['followup'] = v;
                            await p.save(next);
                          });
                        },
                ),
                DropdownButtonFormField<int>(
                  initialValue: prefs['snoozeMinutes'] as int? ?? 10,
                  decoration: const InputDecoration(labelText: 'Snooze length'),
                  items: [
                    for (final m in [5, 10, 20, 30, 60])
                      DropdownMenuItem(value: m, child: Text('$m minutes')),
                  ],
                  onChanged: busy
                      ? null
                      : (v) {
                          run(() async {
                            final next = clone(p.state);
                            next['preferences'] ??= {
                              'snoozeMinutes': 10,
                              'followup': true,
                            };
                            next['preferences']['snoozeMinutes'] = v;
                            await p.save(next);
                          });
                        },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Quiet hours · 22:00–08:00'),
                  value: prefs['quietStart'] != null,
                  onChanged: busy
                      ? null
                      : (v) {
                          run(() async {
                            final next = clone(p.state);
                            next['preferences'] ??= {
                              'snoozeMinutes': 10,
                              'followup': true,
                            };
                            if (v) {
                              next['preferences']['quietStart'] = 22;
                              next['preferences']['quietEnd'] = 8;
                            } else {
                              (next['preferences'] as Map).remove('quietStart');
                              (next['preferences'] as Map).remove('quietEnd');
                            }
                            await p.save(next);
                          });
                        },
                ),
                Text(
                  Platform.isAndroid
                      ? 'Android reminders use system alarms, with inexact delivery until precise-alarm access is allowed. Up to 60 alerts over 14 days; reopen to refill.'
                      : 'Desktop reminder banners require OneStep to stay running and a supported notification service. They do not fire after exit. Keep the app open for timers.',
                ),
                const Text(
                  'Quiet hours omit task/routine alerts, never create a catch-up backlog, and do not silence a focus timer you start.',
                ),
              ]),
              section('Backup and restore', [
                FilledButton(
                  onPressed: busy
                      ? null
                      : () {
                          run(export);
                        },
                  child: const Text('Export JSON backup'),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () {
                          run(() async {
                            final file = await openFile(
                              acceptedTypeGroups: [
                                const XTypeGroup(
                                  label: 'OneStep backup',
                                  extensions: ['json'],
                                  mimeTypes: ['application/json'],
                                ),
                              ],
                            );
                            if (file == null) return;
                            if (await file.length() > 8 * 1024 * 1024)
                              throw const FormatException('Backup too large.');
                            await preview(
                              decodeTransfer(await file.readAsString()),
                            );
                          });
                        },
                  child: const Text('Import and preview'),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () {
                          run(() async {
                            final recovery = Directory(
                              '${p.directory.path}/Recovery',
                            );
                            if (!await recovery.exists()) {
                              setState(() {
                                message = 'No recovery copies yet.';
                              });
                              return;
                            }
                            final files = await recovery
                                .list()
                                .where((f) => f is File)
                                .toList();
                            if (!mounted || files.isEmpty) return;
                            final selected = await showDialog<String>(
                              context: context,
                              builder: (c) => SimpleDialog(
                                title: const Text('Recovery copies'),
                                children: [
                                  for (final f in files)
                                    SimpleDialogOption(
                                      onPressed: () => Navigator.pop(c, f.path),
                                      child: Text(f.uri.pathSegments.last),
                                    ),
                                ],
                              ),
                            );
                            if (selected != null)
                              await preview(
                                decodeTransfer(
                                  await File(selected).readAsString(),
                                ),
                              );
                          });
                        },
                  child: const Text('Restore a recovery copy'),
                ),
                const Text(
                  'JSON exports are readable personal data. Keep them private. A USB file copy uses the same format as Wi-Fi transfers.',
                ),
              ]),
              section('Local Wi-Fi transfer', [
                TextField(
                  controller: host,
                  decoration: const InputDecoration(
                    labelText: 'This device’s private IPv4 address',
                  ),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () {
                          run(() async {
                            final value = await lan.start(
                              p.state,
                              host.text.trim(),
                            );
                            setState(() {
                              invitation = value;
                              message =
                                  'Code expires in 10 minutes. Keep this screen open.';
                            });
                          });
                        },
                  child: const Text('Create pairing code'),
                ),
                if (invitation.isNotEmpty) ...[
                  SelectableText(invitation),
                  OutlinedButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: invitation));
                    },
                    child: const Text('Copy pairing code'),
                  ),
                  TextButton(
                    onPressed: () {
                      lan.stop();
                      setState(() {
                        invitation = '';
                      });
                    },
                    child: const Text('Stop sharing'),
                  ),
                ],
                TextField(
                  controller: code,
                  decoration: const InputDecoration(
                    labelText: 'Paste the sender’s pairing code',
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () {
                          run(() async {
                            await preview(await LanTransfer.receive(code.text));
                          });
                        },
                  child: const Text('Receive and preview'),
                ),
                const Text(
                  'Encrypted, manual snapshot transfer over the same private Wi-Fi, with no internet or server. Keep both apps open. Allow private-network firewall access when prompted. Only share the code with your own devices. This is not automatic merging.',
                ),
              ]),
              section('Optional online account', [
                const Text(
                  'Use Bank and rewards above for beta enrollment and securely stored account sessions. Your local planner profile works independently.',
                ),
              ]),
              section('About this beta', [
                const Text(
                  'OneStep · 0.6.0 beta\nApplication identity: meow.tira.onestep',
                ),
                const Text(
                  'iOS keeps its native SwiftUI app and Live Activity. Android uses Material 3. Desktop clients require their bundled libraries; keep the Windows distribution folder together.',
                ),
                const SelectableText(
                  'Builds: https://github.com/sillytira/onestep-ios/actions',
                ),
                const Text(
                  'Optional family services include approved rewards, private Kids accounts, rankings, and parent codes. OS app-time blocking is not enabled. Native updates require a new package; iOS signing still applies.',
                ),
              ]),
              if (busy) const LinearProgressIndicator(),
              if (message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: SelectableText(message),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

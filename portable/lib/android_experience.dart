import 'localization.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'family.dart';
import 'model.dart';
import 'services.dart';
import 'personal.dart';

const betaVersion = '0.10.0 Beta';

class BetaBadge extends StatelessWidget {
  const BetaBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xffb6a4ff).withValues(alpha: .16),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const LText(
      'BETA',
      style: TextStyle(
        color: Color(0xffcbbcff),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    ),
  );
}

/// Short, interruptible transitions; system reduced-motion preference wins.
class PageMotion extends StatelessWidget {
  final Widget child;
  final Object identity;
  const PageMotion({super.key, required this.child, required this.identity});
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220),
    reverseDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 120),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    layoutBuilder: (current, previous) => Stack(
      fit: StackFit.expand,
      children: [
        for (final old in previous)
          ExcludeSemantics(child: IgnorePointer(child: old)),
        if (current != null) current,
      ],
    ),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .025),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: KeyedSubtree(key: ValueKey(identity), child: child),
  );
}

class AndroidMore extends StatelessWidget {
  final VoidCallback? calendar, sync;
  final VoidCallback notes,
      history,
      library,
      settings,
      backups,
      wifi,
      xp,
      family;
  const AndroidMore({
    super.key,
    this.calendar, this.sync,
    required this.notes,
    required this.history,
    required this.library,
    required this.settings,
    required this.backups,
    required this.wifi,
    required this.xp,
    required this.family,
  });
  Widget entry(
    String title,
    String detail,
    IconData icon,
    Color color,
    VoidCallback action,
  ) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, color: color),
      ),
      title: LText(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: LText(detail),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: action,
    ),
  );
  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('android-more'),
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
    children: [
      const Row(
        children: [
          Expanded(
            child: LText(
              'Your space',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
          ),
          BetaBadge(),
        ],
      ),
      const SizedBox(height: 8),
      const LText('The extras, without crowding your next step.'),
      const SizedBox(height: 16),
      if(calendar!=null) entry('Planner','Day, week and month overview',Icons.calendar_month_rounded,const Color(0xff89b8ff),calendar!),
      if(sync!=null) entry('Private planner sync','Automatic encrypted sync with conflict review',Icons.sync_lock_rounded,const Color(0xff77e0d6),sync!),
      entry(
        'XP Beta',
        'Your progress, pending awards and separate rankings',
        Icons.bolt_rounded,
        const Color(0xffc3a3ff),
        xp,
      ),
      entry(
        'Notes',
        'Capture a thought for later',
        Icons.edit_note_rounded,
        const Color(0xffffc47e),
        notes,
      ),
      entry(
        'History',
        'Tasks and routines you have finished',
        Icons.history_rounded,
        const Color(0xff6bdfbd),
        history,
      ),
      entry(
        'Routine library & updates',
        'Preview and add fresh routine packs',
        Icons.auto_stories_rounded,
        const Color(0xff89b8ff),
        library,
      ),
      entry(
        'Backups and restore',
        'Export before updating or moving devices',
        Icons.cloud_download_outlined,
        const Color(0xff9bb6ff),
        backups,
      ),
      entry(
        'Local Wi-Fi transfer',
        'Pair devices and transfer an encrypted snapshot',
        Icons.wifi_rounded,
        const Color(0xff77e0d6),
        wifi,
      ),
      entry(
        'Family and accounts',
        'Bank, parent approvals and private kids accounts',
        Icons.family_restroom_rounded,
        const Color(0xffff9fc8),
        family,
      ),
      entry(
        'Reminders and settings',
        'Permissions, test reminder, quiet hours and snooze',
        Icons.notifications_active_outlined,
        const Color(0xffffd079),
        settings,
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LText(
                'Focus & app time',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const LText(
                'Focus timers and reminders work here. Apple Screen Time and Live Activities are iPhone features. Android app blocking is not included in this beta.',
              ),
              TextButton(
                onPressed: settings,
                child: const LText('Check reminder setup'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      const Center(child: Text('OneStep $betaVersion · offline first')),
    ],
  );
}

class XPBetaPage extends StatefulWidget {
  final Planner planner;
  final Future<void> Function() account, rankings;
  final FamilyClient? client;
  const XPBetaPage({
    super.key,
    required this.planner,
    required this.account,
    required this.rankings,
    this.client,
  });
  @override
  State<XPBetaPage> createState() => _XPBetaPageState();
}

class _XPBetaPageState extends State<XPBetaPage> {
  late final client = widget.client ?? FamilyClient.shared;
  bool loading = true, connected = false;
  int? total, today;
  int pending = 0;
  String? owner;
  String status = 'Checking your account…';
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      connected = false;
    });
    try {
      await client.load();
      final user = client.userID;
      if (owner != user) {
        total = null;
        today = null;
        pending = 0;
        owner = user;
      }
      if (!client.signedIn || user == null) {
        status =
            'Sign in to start earning account XP. Your offline planner needs no account.';
      } else {
        if (widget.client == null)
          await syncPersonalTasks(widget.planner.state);
        final saved = await FamilyClient.vault.read(key: 'xp.receipts.$user');
        final receipts = saved == null
            ? <String, dynamic>{}
            : jsonDecode(saved) as Json;
        pending = rows(widget.planner.state, 'xpCompletions')
            .where(
              (e) =>
                  e['accountID'] == user.toLowerCase() &&
                  receipts[e['eventKey']] != -1,
            )
            .length;
        try {
          final result = await client.rpc('onestep_economy_status', {}) as Map;
          if (client.userID != user) return;
          if (result['version'] != 6)
            throw const FormatException('XP setup needed');
          total = (result['xp_total'] as num).toInt();
          today = (result['xp_today'] as num).toInt();
          connected = true;
          status =
              'Server-confirmed XP. Pending completions retry while OneStep is open.';
        } catch (_) {
          status =
              'XP sync needs a connection and the beta service upgrade. Pending completions stay saved; they are not confirmed XP yet.';
        }
      }
    } catch (_) {
      status =
          'Could not load your account. Your planner and completions are safe.';
    } finally {
      if (mounted)
        setState(() {
          loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LText('XP Beta'),
      actions: [
        IconButton(
          tooltip: 'Refresh XP',
          onPressed: loading ? null : refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              colors: [Color(0xff433263), Color(0xff1b243d)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.bolt_rounded, color: Color(0xffd7c1ff)),
                  SizedBox(width: 8),
                  LText('YOUR PROGRESS'),
                  Spacer(),
                  BetaBadge(),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                total == null ? 'Let’s begin' : '$total XP',
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const LText('XP celebrates progress. Points buy app time. Beta earnings stay in the beta leaderboard cohort.'),
              if (today != null) ...[
                const SizedBox(height: 20),
                Text('$today / 1,000 XP today'),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (today! / 1000).clamp(0, 1),
                  borderRadius: BorderRadius.circular(8),
                ),
              ],
            ],
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        const SizedBox(height: 18),
        Text(status, semanticsLabel: status),
        if (pending > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '$pending completion${pending == 1 ? '' : 's'} waiting to sync',
              style: const TextStyle(color: Color(0xffffd079)),
            ),
          ),
        const SizedBox(height: 18),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LText(
                  'One small step = 10 XP',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 10),
                LText(
                  'Complete a task or daily routine step while signed in. Earn up to 1,000 XP per UTC day. Undoing, re-completing or importing the same completion cannot multiply awards.',
                ),
                SizedBox(height: 10),
                LText(
                  'XP is separate from spendable points. Skipping, snoozing and opening the app do not earn XP. Children stay off public leaderboards.',
                ),
              ],
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: () async {
            await widget.account();
            if (mounted) await refresh();
          },
          icon: const Icon(Icons.person_outline_rounded),
          label: const LText('Account and XP privacy'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: connected && client.accountKind != 'kids'
              ? widget.rankings
              : null,
          icon: const Icon(Icons.leaderboard_outlined),
          label: const LText('Separate XP leaderboard'),
        ),
      ],
    ),
  );
}

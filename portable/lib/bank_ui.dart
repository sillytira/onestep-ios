import 'package:flutter/material.dart';
import 'model.dart';

bool bankSectionVisible(String title, int tab) {
  if (title == 'OneStep accounts' || title == 'Your account') return true;
  if (title == 'Your points') return tab == 0;
  if (title == 'Transactions') return tab == 1;
  if (title == 'This week: opt-in rankings') return tab == 3;
  if (title == 'Public profile' ||
      title == 'Where to use your account' ||
      title == 'Reconnect this account')
    return tab == 4;
  return tab == 2;
}

class BankOverview extends StatelessWidget {
  const BankOverview({
    super.key,
    required this.balance,
    required this.name,
    required this.ledger,
    required this.onActivity,
    required this.onAccount,
    required this.onFamily,
    required this.familyAccount,
  });
  final int? balance;
  final String name;
  final List<Json> ledger;
  final VoidCallback onActivity, onAccount, onFamily;
  final bool familyAccount;
  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final recent = ledger.where((e) {
      final at = DateTime.tryParse(e['created_at'] as String? ?? '')?.toLocal();
      return at != null &&
          at.year == today.year &&
          at.month == today.month &&
          at.day == today.day;
    });
    final earned = recent.fold<int>(
      0,
      (sum, e) =>
          sum +
          ((e['delta'] as num).toInt() > 0 ? (e['delta'] as num).toInt() : 0),
    );
    final spent = recent.fold<int>(
      0,
      (sum, e) =>
          sum +
          ((e['delta'] as num).toInt() < 0 ? -(e['delta'] as num).toInt() : 0),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        Text(
          'POINTS ACCOUNT',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            letterSpacing: 2,
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          balance?.toString() ?? '—',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w700,
            letterSpacing: -3,
          ),
        ),
        const Text(
          'Available points',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 20,
          runSpacing: 12,
          children: [
            _action(
              context,
              Icons.receipt_long_rounded,
              'Activity',
              onActivity,
            ),
            if (familyAccount)
              _action(
                context,
                Icons.family_restroom_rounded,
                'Family',
                onFamily,
              ),
            _action(
              context,
              Icons.person_outline_rounded,
              'Account',
              onAccount,
            ),
          ],
        ),
        const SizedBox(height: 30),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff6b54bd), Color(0xff282248), Color(0xff15151d)],
            ),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.blur_on_rounded, color: Color(0xffd5c7ff)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'OneStep',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(Icons.auto_awesome, color: Color(0xffd5c7ff)),
                ],
              ),
              const SizedBox(height: 40),
              Text(
                name.isEmpty ? 'Your points account' : name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Earned, one step at a time.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              const Text(
                'VIRTUAL POINTS · NO CASH VALUE',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _summary(
                'Earned today',
                '+$earned',
                const Color(0xff78e4bb),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _summary('Used today', '−$spent', const Color(0xffc2afff)),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent activity',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: onActivity, child: const Text('See all')),
          ],
        ),
        if (ledger.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Your earned points and rewards will appear here.',
              style: TextStyle(color: Colors.white60),
            ),
          ),
        for (final entry in ledger.take(4)) BankTransaction(entry: entry),
      ],
    );
  }

  Widget _summary(String title, String value, Color color) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xff1a1b20),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white60)),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );
  Widget _action(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback action,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton.filledTonal(
        onPressed: action,
        icon: Icon(icon),
        tooltip: label,
        style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
      ),
      const SizedBox(height: 6),
      Text(label),
    ],
  );
}

class BankTransaction extends StatelessWidget {
  const BankTransaction({super.key, required this.entry});
  final Json entry;
  @override
  Widget build(BuildContext context) {
    final delta = (entry['delta'] as num).toInt(), positive = delta > 0;
    final date = DateTime.tryParse(
      entry['created_at'] as String? ?? '',
    )?.toLocal();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 5),
      leading: CircleAvatar(
        backgroundColor: positive
            ? const Color(0xff18392f)
            : const Color(0xff2d2745),
        child: Icon(
          positive ? Icons.arrow_downward_rounded : Icons.lock_open_rounded,
          color: positive ? const Color(0xff78e4bb) : const Color(0xffc2afff),
        ),
      ),
      title: Text(
        entry['reason'] as String? ?? 'Points activity',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: date == null
          ? null
          : Text(
              '${date.day}/${date.month} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
            ),
      trailing: Text(
        '${positive ? '+' : ''}$delta',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: positive ? const Color(0xff78e4bb) : Colors.white,
        ),
      ),
    );
  }
}

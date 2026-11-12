import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'model.dart';
import 'parent_pin.dart';
import 'connection.dart';
import 'bank_ui.dart';

/// Public connection defaults ship with the app; user sessions remain in secure storage.
class FamilyClient {
  static final shared = FamilyClient();
  Future<void>? _loading;
  Future<void> load() => _loading ??= _load().catchError((Object error) {
    _loading = null;
    throw error;
  });
  static const vault = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  String project = serviceURL, publicKey = servicePublishableKey;
  Json? session;
  String? accountKind;
  Future<void>? _refreshing;
  bool get signedIn => session?['access_token'] is String;
  String? get userID => session?['user']?['id'] as String?;
  Future<void> _load() async {
    final config = await vault.read(key: 'family.connection');
    if (config != null) {
      final value = jsonDecode(config) as Json;
      project = value['url'] as String;
      publicKey = value['key'] as String;
    }
    final saved = await vault.read(key: 'family.session');
    if (saved != null) session = jsonDecode(saved) as Json;
    accountKind = await vault.read(key: 'family.kind');
  }

  Future<void> configure(String url, String key) async {
    final uri = Uri.parse(url.trim());
    bool allowed = key.trim().startsWith('sb_publishable_');
    try {
      final parts = key.trim().split('.');
      if (parts.length == 3)
        allowed =
            (jsonDecode(
                  utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
                )
                as Map)['role'] ==
            'anon';
    } catch (_) {}
    if (uri.scheme != 'https' ||
        !uri.host.endsWith('.supabase.co') ||
        uri.path.isNotEmpty && uri.path != '/' ||
        !allowed)
      throw const FormatException(
        'Use the Supabase HTTPS project URL and publishable/anon key. Secret keys are forbidden.',
      );
    if (project != uri.origin) await signOut();
    project = uri.origin;
    publicKey = key.trim();
    await vault.write(
      key: 'family.connection',
      value: jsonEncode({'url': project, 'key': publicKey}),
    );
  }

  Future<dynamic> request(
    String path, {
    Json? body,
    bool authenticated = true,
  }) async {
    if (project.isEmpty || publicKey.isEmpty)
      throw const FormatException('Set up the connection first.');
    if (authenticated) {
      if (!signedIn) throw const FormatException('Sign in first.');
      await refreshSession();
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.openUrl(
        body == null ? 'GET' : 'POST',
        Uri.parse(project + path),
      );
      request.followRedirects = false;
      request.headers.set('apikey', publicKey);
      if (authenticated)
        request.headers.set(
          'Authorization',
          'Bearer ${session!['access_token']}',
        );
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024)
          throw const FormatException('Service response too large.');
      }
      final text = utf8.decode(bytes);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = 'Service request failed (${response.statusCode}).';
        try {
          final json = jsonDecode(text) as Map;
          message =
              (json['msg'] ??
                      json['message'] ??
                      json['error_description'] ??
                      message)
                  .toString();
        } catch (_) {}
        throw FormatException(message);
      }
      return text.isEmpty ? null : jsonDecode(text);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> acceptSession(dynamic response) async {
    if (response is! Map || response['access_token'] is! String)
      throw const FormatException(
        'Check your email to confirm your account, then sign in.',
      );
    final next = Map<String,dynamic>.from(response);
    if (next['user']?['id'] != userID) {
      accountKind = null;
      await vault.delete(key:'family.kind');
    }
    session = next;
    session!['expires_at'] ??=
        DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        (session!['expires_in'] as int? ?? 3600);
    await vault.write(key: 'family.session', value: jsonEncode(session));
  }

  Future<void> refreshSession() async {
    if ((session?['expires_at'] as num? ?? 0) >
        DateTime.now().millisecondsSinceEpoch / 1000 + 60)
      return;
    final refresh = session?['refresh_token'];
    if (refresh is! String)
      throw const FormatException('Please sign in again.');
    if (_refreshing != null) return _refreshing!;
    final pending = () async {
      final updated = await request(
          '/auth/v1/token?grant_type=refresh_token',
          body: {'refresh_token': refresh},
          authenticated: false,
        );
      if (session?['refresh_token'] != refresh) throw const FormatException('Account changed. Please retry.');
      await acceptSession(updated);
    }();
    _refreshing = pending;
    try {
      await pending;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> signIn(String email, String password) async => acceptSession(
    await request(
      '/auth/v1/token?grant_type=password',
      body: {'email': email.trim(), 'password': password},
      authenticated: false,
    ),
  );
  Future<void> signUp(
    String email,
    String password,
    String betaKey,
    String username,
  ) async => acceptSession(
    await request(
      '/auth/v1/signup',
      body: {
        'email': email.trim(),
        'password': password,
        'data': {'beta_key': betaKey.trim(), 'username': username.trim()},
      },
      authenticated: false,
    ),
  );
  Future<void> signOut({bool parentAuthorized = false}) async {
    if (signedIn &&
        (accountKind == 'kids' || accountKind == null) &&
        !parentAuthorized)
      throw const FormatException(
        'Parent authorization is required to sign out of a Kids account.',
      );
    final token = session?['access_token'];
    try {
      if (token != null) await request('/auth/v1/logout', body: {});
    } catch (_) {}
    final id = userID;
    session = null;
    accountKind = null;
    await vault.delete(key: 'family.session');
    await vault.delete(key: 'family.kind');
    await vault.delete(key: 'family.childVerifier.$id');
    await vault.delete(key: 'family.childCache.$id');
  }

  Future<dynamic> rpc(String name, Json args) =>
      request('/rest/v1/rpc/$name', body: args);
  Future<List<Json>> list(String query) async =>
      (await request('/rest/v1/$query') as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Future<bool> unlockOffline(String code) async {
    final lockText = await vault.read(key: 'family.pinLock.$userID');
    final lock = lockText == null
        ? <String, dynamic>{}
        : jsonDecode(lockText) as Json;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now < (lock['until'] as int? ?? 0) ||
        now < (lock['lastAttempt'] as int? ?? 0) - 60000)
      throw const FormatException(
        'Parent code is temporarily locked. Check the clock and try again later.',
      );
    final saved = await vault.read(key: 'family.childVerifier.$userID');
    if (saved == null)
      throw const FormatException(
        'Your parent must set up the offline code and sync this device first.',
      );
    final good = await ParentPin.matches(code, jsonDecode(saved) as Json);
    final failures = good ? 0 : (lock['failures'] as int? ?? 0) + 1;
    await vault.write(
      key: 'family.pinLock.$userID',
      value: jsonEncode({
        'failures': failures,
        'until': failures >= 5 ? now + 15 * 60 * 1000 : 0,
        'lastAttempt': now,
      }),
    );
    return good;
  }
}

class RewardsPage extends StatefulWidget {
  final String role;
  final FamilyClient? client;
  const RewardsPage({super.key, this.role = 'bank', this.client});
  @override
  State<RewardsPage> createState() => _RewardsPageState();
}

class AdminPage extends StatefulWidget {
  final FamilyClient client;
  const AdminPage({super.key, required this.client});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final boundEmail = TextEditingController(),
      delta = TextEditingController(),
      reason = TextEditingController();
  String kind = 'normal', message = '', issuedCode = '';
  bool busy = false;
  List<Json> users = [];
  String? selected;
  @override
  void initState() {
    super.initState();
    run(load);
  }

  @override
  void dispose() {
    boundEmail.dispose();
    delta.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final response = await widget.client.rpc('onestep_admin_users', {});
    if (mounted)
      setState(() {
        users = (response as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Application admin')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Server-authorized administration',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Only an enrolled owner/admin can use these actions. Database passwords and service-role keys are never available in the app. Points are virtual and cannot be sold.',
            ),
            const SizedBox(height: 24),
            if (busy) const LinearProgressIndicator(),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(message),
              ),
            DropdownButtonFormField<String>(
              initialValue: kind,
              decoration: const InputDecoration(labelText: 'Beta account type'),
              items: const [
                DropdownMenuItem(value: 'normal', child: Text('Normal')),
                DropdownMenuItem(value: 'parent', child: Text('Parent')),
                DropdownMenuItem(value: 'kids', child: Text('Kids')),
              ],
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      kind = v ?? 'normal';
                    }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: boundEmail,
              decoration: const InputDecoration(
                labelText: 'Bind invitation to email (optional)',
              ),
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy
                  ? null
                  : () {
                      run(() async {
                        final code = await widget.client
                            .rpc('onestep_issue_beta_key', {
                              'account_kind': kind,
                              'bound_email': boundEmail.text.trim(),
                            });
                        setState(() {
                          issuedCode = code as String;
                        });
                      });
                    },
              child: const Text('Generate single-use beta key'),
            ),
            if (issuedCode.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText(issuedCode),
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: issuedCode));
                },
                child: const Text('Copy private enrollment key'),
              ),
              const Text(
                'Shown once here. Share privately with the intended user; expires after 7 days. No key is saved in source or analytics.',
              ),
            ],
            const SizedBox(height: 28),
            const Text(
              'Accounts and audited adjustments',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () {
                      run(load);
                    },
              child: const Text('Refresh accounts'),
            ),
            for (final user in users)
              RadioListTile<String>(
                value: user['id'] as String,
                groupValue: selected,
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                        selected = v;
                      }),
                title: Text(user['email'] as String? ?? user['id'] as String),
                subtitle: Text(
                  '${user['kind'] ?? 'legacy'} · ${user['points']} points',
                ),
              ),
            TextField(
              controller: delta,
              decoration: const InputDecoration(
                labelText: 'Point adjustment, −10000 to 10000',
              ),
              keyboardType: const TextInputType.numberWithOptions(signed: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration: const InputDecoration(
                labelText: 'Audit reason (required)',
              ),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy || selected == null
                  ? null
                  : () {
                      run(() async {
                        final amount = int.tryParse(delta.text);
                        if (amount == null ||
                            amount == 0 ||
                            amount.abs() > 10000 ||
                            reason.text.trim().length < 3)
                          throw const FormatException(
                            'Choose a non-zero amount and an audit reason.',
                          );
                        final event = uuid.v4();
                        final result = await widget.client
                            .rpc('onestep_admin_adjust_points', {
                              'target': selected,
                              'amount': amount,
                              'explanation': reason.text.trim(),
                              'event': event,
                            });
                        await load();
                        setState(() {
                          message = 'Adjustment recorded. New balance: $result';
                          delta.clear();
                          reason.clear();
                        });
                      });
                    },
              child: const Text('Record audited adjustment'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RewardsPageState extends State<RewardsPage> with WidgetsBindingObserver {
  late final client = widget.client ?? FamilyClient.shared;
  final url = TextEditingController(),
      key = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  final familyName = TextEditingController(text: 'Our family'),
      nickname = TextEditingController(),
      invite = TextEditingController(),
      taskTitle = TextEditingController(),
      reward = TextEditingController(text: '5');
  final betaKey = TextEditingController(), username = TextEditingController();
  final publicName = TextEditingController(), handle = TextEditingController();
  bool optIn = false;
  String rankingMetric = "tasks";
  bool screenUnlockAllowed = false;
  int screenMinuteCost = 1, screenDailyMinutes = 120;
  List<Json> screenPolicies = [];
  bool screenPoliciesLoaded = false;
  int policyRevision = 0;
  void selectPolicy(String? child) {
    policyDirty = false;
    selectedChild = child;
    final matches = screenPolicies.where((p) => p['user_id'] == child);
    final policy = matches.isEmpty ? null : matches.first;
    screenUnlockAllowed = policy?['enabled'] == true;
    screenMinuteCost = (policy?['cost_per_minute'] as num?)?.toInt() ?? 1;
    screenDailyMinutes = (policy?['daily_minutes'] as num?)?.toInt() ?? 120;
    policyRevision++;
  }

  List<Json> ledger = [],
      tasks = [],
      children = [],
      families = [],
      rankings = [];
  int balance = 0;
  String message = '', generatedInvite = '';
  String? selectedChild;
  bool busy = true;
  bool externalBank = false;
  int bankTab = 0;
  bool policyDirty = false;
  bool ready = false;
  bool admin = false;
  bool hasSnapshot = false;
  String lastSync = '';
  Timer? poll;
  String get effectiveRole => client.signedIn
      ? (client.accountKind == 'parent' ? 'parent' : client.accountKind == 'kids' ? 'kids' : 'bank')
      : widget.role;
  String get appName => effectiveRole == 'parent'
      ? 'OneStep Parent'
      : effectiveRole == 'kids'
      ? 'OneStep Kids'
      : 'OneStep Bank';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initialize();
  }

  Future<void> initialize() async {
    try {
      await client.load();
      url.text = client.project;
      key.text = client.publicKey;
      externalBank =
          await FamilyClient.vault.read(key: 'family.externalBank') == 'true';
      final cached = await FamilyClient.vault.read(
        key: 'family.snapshot.${client.userID}',
      );
      if (cached != null) {
        final saved = jsonDecode(cached) as Json;
        balance = (saved['balance'] as num).toInt();
        ledger = rows(saved, 'ledger');
        tasks = rows(saved, 'tasks');
        children = rows(saved, 'children');
        families = rows(saved, 'families');
        rankings = rows(saved, 'rankings');
        publicName.text = saved['publicName'] as String? ?? '';
        handle.text = saved['handle'] as String? ?? '';
        optIn = saved['optIn'] == true;
        lastSync = saved['lastSync'] as String? ?? '';
        hasSnapshot = true;
      }
      if (children.isNotEmpty)
        selectedChild = children.first['child_id'] as String;
      if (client.signedIn) await refresh();
    } catch (e) {
      message = '$e';
    } finally {
      if (mounted)
        setState(() {
          busy = false;
          ready = true;
        });
    }
    poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && client.signedIn && !busy) run(refresh, quiet: true);
    });
  }

  @override
  void dispose() {
    poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [
      url,
      key,
      email,
      password,
      familyName,
      nickname,
      invite,
      taskTitle,
      reward,
      betaKey,
      username,
      publicName,
      handle,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ready && client.signedIn && !busy)
      run(refresh, quiet: true);
  }

  Future<void> run(Future<void> Function() action, {bool quiet = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      if (!quiet) message = '';
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

  Future<void> refresh() async {
    final kinds = await client.list(
      'onestep_account_kinds?select=kind&limit=1',
    );
    if (kinds.isEmpty)
      throw const FormatException('Account enrollment is not configured.');
    client.accountKind = kinds.first['kind'] as String;
    await FamilyClient.vault.write(
      key: 'family.kind',
      value: client.accountKind,
    );
    final values = await Future.wait<dynamic>([
      client.rpc('onestep_my_balance', {}),
      client.list(
        'onestep_points_ledger?select=event_id,delta,reason,created_at&user_id=eq.${client.userID}&order=created_at.desc&limit=100',
      ),
      client.list(
        'onestep_family_tasks?select=*&order=updated_at.desc&limit=100',
      ),
      client.list(
        'onestep_children?select=child_id,nickname&active=eq.true&limit=100',
      ),
      client.list('onestep_families?select=id,name&limit=1'),
    ]);
    final own = await client.list(
      'onestep_children?select=child_id,offline_pin_verifier,active&child_id=eq.${client.userID}&limit=1',
    );
    if (own.isNotEmpty &&
        own.first['active'] == true &&
        own.first['offline_pin_verifier'] is Map)
      await FamilyClient.vault.write(
        key: 'family.childVerifier.${client.userID}',
        value: jsonEncode(own.first['offline_pin_verifier']),
      );
    admin = await client.rpc('onestep_is_admin', {}) as bool;
    screenPoliciesLoaded = false;
    try {
      screenPolicies = await client.list(
        'onestep_screen_time_policies?select=user_id,enabled,cost_per_minute,daily_minutes&limit=100',
      );
      screenPoliciesLoaded = true;
    } catch (_) { message = 'App-time policy could not refresh. Account data is still available.'; }
    if (client.accountKind != 'kids') try {
      rankings =
          (await client.rpc('onestep_rankings', {'metric': rankingMetric})
                  as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
    } catch (_) { message = 'Rankings could not refresh. Your account data is still available.'; }
    if (publicName.text.isEmpty) {
      final profile = await client.list(
        'onestep_profiles?select=display_name,handle,leaderboard_opt_in&limit=1',
      );
      if (profile.isNotEmpty) {
        publicName.text = profile.first['display_name'] as String;
        handle.text = profile.first['handle'] as String? ?? '';
        optIn = profile.first['leaderboard_opt_in'] == true;
      }
    }
    await FamilyClient.vault.write(
      key: 'family.childCache.${client.userID}',
      value: jsonEncode(values[3]),
    );
    if (!mounted) return;
    setState(() {
      balance = (values[0] as num).toInt();
      ledger = values[1] as List<Json>;
      tasks = values[2] as List<Json>;
      children = values[3] as List<Json>;
      families = values[4] as List<Json>;
      lastSync = DateTime.now().toLocal().toString().split('.').first;
      hasSnapshot = true;
      if (selectedChild == null && children.isNotEmpty)
        selectedChild = children.first['child_id'] as String;
      if (!policyDirty) selectPolicy(selectedChild);
    });
    await FamilyClient.vault.write(
      key: 'family.snapshot.${client.userID}',
      value: jsonEncode({
        'balance': balance,
        'ledger': ledger,
        'tasks': tasks,
        'children': children,
        'families': families,
        'rankings': rankings,
        'publicName': publicName.text,
        'handle': handle.text,
        'optIn': optIn,
        'lastSync': lastSync,
      }),
    );
  }

  Future<void> childSignOut() async {
    final input = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Parent authorization'),
        content: TextField(
          controller: input,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '10-digit parent code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, input.text),
            child: const Text('Authorize device sign-out'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value == null) return;
    if (!await client.unlockOffline(value))
      throw const FormatException('Incorrect parent code.');
    await client.signOut(parentAuthorized: true);
    setState(() {
      admin = false; screenPoliciesLoaded = false; bankTab = 0;
      tasks = [];
      children = [];
      families = [];
      ledger = [];
      balance = 0;
      hasSnapshot = false;
      lastSync = '';
      rankings = [];
      publicName.clear();
      handle.clear();
    });
  }

  Widget panel(String title, List<Widget> content, {Color? color}) {
    if (client.signedIn && !bankSectionVisible(title, bankTab)) return const SizedBox.shrink();
    return Card(
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: color == null
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                colors: [color.withValues(alpha: .35), const Color(0xff1c1d21)],
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          for (final child in content) ...[child, const SizedBox(height: 12)],
        ],
      ),
    ),
  );
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(appName),
      actions: [
        if (client.signedIn)
          IconButton(
            tooltip: 'Refresh account',
            onPressed: busy
                ? null
                : () {
                    run(refresh);
                  },
            icon: const Icon(Icons.refresh),
          ),
      ],
    ),
    bottomNavigationBar: !client.signedIn ? null : NavigationBar(
      selectedIndex: [0,1,if(effectiveRole!='bank')2,if(client.accountKind!='kids')3,4].indexOf(bankTab).clamp(0,4),
      onDestinationSelected:(i)=>setState(()=>bankTab=[0,1,if(effectiveRole!='bank')2,if(client.accountKind!='kids')3,4][i]),
      destinations: [
        const NavigationDestination(icon:Icon(Icons.account_balance_wallet_outlined),selectedIcon:Icon(Icons.account_balance_wallet),label:'Home'),
        const NavigationDestination(icon:Icon(Icons.receipt_long_outlined),label:'Activity'),
        if(effectiveRole!='bank') const NavigationDestination(icon:Icon(Icons.family_restroom),label:'Family'),
        if(client.accountKind!='kids') const NavigationDestination(icon:Icon(Icons.leaderboard_outlined),label:'Rankings'),
        const NavigationDestination(icon:Icon(Icons.person_outline),label:'Account'),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (busy) const LinearProgressIndicator(),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: SelectableText(message),
              ),
            if (!client.signedIn) ...[
              panel('OneStep accounts', [
                const Text(
                  'Connected to the main OneStep service. Sign in or enter your admin-issued beta key to create an account.',
                ),
              ]),
              panel('Your account', [
                const Text(
                  'Use the same service and account in Bank, Kids, and OneStep. A parent and child need separate accounts. Family roles are enforced by the service; installing Parent does not grant access to another family.',
                ),
                TextField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                ),
                TextField(
                  controller: password,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  autocorrect: false,
                ),
                TextField(
                  controller: betaKey,
                  decoration: const InputDecoration(
                    labelText: 'Single-use beta key (new accounts)',
                  ),
                  obscureText: true,
                  autocorrect: false,
                ),
                if (effectiveRole != 'kids')
                  TextField(
                    controller: username,
                    decoration: const InputDecoration(
                      labelText: 'Handle for a new account',
                    ),
                    autocorrect: false,
                  ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () {
                          run(() async {
                            await client.configure(url.text, key.text);
                            await client.signIn(email.text, password.text);
                            password.clear();
                            await refresh();
                          });
                        },
                  child: const Text('Sign in'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          run(() async {
                            await client.configure(url.text, key.text);
                            await client.signUp(
                              email.text,
                              password.text,
                              betaKey.text,
                              username.text,
                            );
                            password.clear();
                            betaKey.clear();
                            await refresh();
                          });
                        },
                  child: const Text('Create beta account'),
                ),
                const Text(
                  'An admin-issued beta key is required. Email confirmation is not required once the service is configured for this beta. Signing in sends credentials to the selected service; only family-assigned tasks are shared. Your private planner is never uploaded automatically.',
                ),
              ]),
            ] else ...[
              Text(
                client.accountKind == 'kids'
                    ? (client.session?['user']?['email'] as String? ??
                          'Kids account')
                    : '@${handle.text}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                hasSnapshot
                    ? 'Last synced: $lastSync · saved account snapshot'
                    : 'Connect to load your account. No saved balance yet.',
              ),
              const SizedBox(height: 12),
              if (admin && bankTab == 4)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AdminPage(client: client),
                      ),
                    );
                  },
                  icon: const Icon(Icons.admin_panel_settings),
                  label: const Text('Application admin console'),
                ),
              if (bankTab == 0) BankOverview(
                balance: hasSnapshot ? balance : null,
                name: effectiveRole == 'kids' ? 'OneStep Kids' : '@${handle.text}',
                ledger: ledger,
                familyAccount: effectiveRole == 'parent' || effectiveRole == 'kids',
                onActivity: ()=>setState(()=>bankTab=1),
                onAccount: ()=>setState(()=>bankTab=4),
                onFamily: ()=>setState(()=>bankTab=2),
              ),
              if (effectiveRole == 'parent') ...[
                if (families.isEmpty)
                  panel('Start your family', [
                    TextField(
                      controller: familyName,
                      decoration: const InputDecoration(
                        labelText: 'Family name',
                      ),
                    ),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () {
                              run(() async {
                                await client.rpc('onestep_create_family', {
                                  'family_name': familyName.text.trim(),
                                });
                                await refresh();
                              });
                            },
                      child: const Text('Create parent family'),
                    ),
                    const Text(
                      'This is a trusted-family beta. An invitation links accounts; it does not verify age or legal guardianship and does not authorize Apple Screen Time.',
                    ),
                  ])
                else
                  panel(families.first['name'] as String, [
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () {
                              run(() async {
                                final code = await client.rpc(
                                  'onestep_create_family_invite',
                                  {},
                                );
                                setState(() {
                                  generatedInvite = code as String;
                                });
                              });
                            },
                      child: const Text('Create 10-minute child invitation'),
                    ),
                    if (generatedInvite.isNotEmpty) ...[
                      SelectableText(generatedInvite),
                      OutlinedButton(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: generatedInvite),
                          );
                        },
                        child: const Text('Copy invitation'),
                      ),
                      const Text(
                        'Share privately with your child. Single use; creating another code revokes the previous one.',
                      ),
                    ],
                  ]),
                if (children.isNotEmpty)
                  panel('Assign a small task', [
                    DropdownButtonFormField<String>(
                      key: ValueKey('assign-$selectedChild'),
                      initialValue: selectedChild,
                      decoration: const InputDecoration(labelText: 'Child'),
                      items: children
                          .map(
                            (c) => DropdownMenuItem(
                              value: c['child_id'] as String,
                              child: Text(c['nickname'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (id) => setState(() {
                              selectPolicy(id);
                            }),
                    ),
                    TextField(
                      controller: taskTitle,
                      decoration: const InputDecoration(
                        labelText: 'One clear task',
                      ),
                    ),
                    TextField(
                      controller: reward,
                      decoration: const InputDecoration(
                        labelText: 'Points, 1–1000',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () {
                              run(() async {
                                final points = int.tryParse(reward.text);
                                if (points == null ||
                                    points < 1 ||
                                    points > 1000 ||
                                    taskTitle.text.trim().isEmpty)
                                  throw const FormatException(
                                    'Enter a task and 1–1000 points.',
                                  );
                                await client.rpc('onestep_assign_family_task', {
                                  'child': selectedChild,
                                  'task_title': taskTitle.text.trim(),
                                  'reward': points,
                                });
                                taskTitle.clear();
                                await refresh();
                              });
                            },
                      child: const Text('Assign task'),
                    ),
                  ]),
                if (children.isNotEmpty)
                  panel('Apple app-time policy', [
                    Text(
                      'Policy for ${children.where((c) => c["child_id"] == selectedChild).map((c) => c["nickname"]).join()}. This permits purchases on the entitled native iPhone app; Apple authorization is separate.',
                    ),
                    SwitchListTile(
                      title: const Text('Allow points-funded unlocks'),
                      value: screenUnlockAllowed,
                      onChanged: busy ? null : (v) => setState(() { screenUnlockAllowed = v; policyDirty = true; }),
                    ),
                    DropdownButtonFormField<int>(
                      key: ValueKey('price-$policyRevision'),
                      initialValue: screenMinuteCost,
                      decoration: const InputDecoration(
                        labelText: 'Points per minute',
                      ),
                      items: [
                        for (var i = 1; i <= 10; i++)
                          DropdownMenuItem(value: i, child: Text('$i')),
                      ],
                      onChanged: busy ? null : (v) => setState(() { screenMinuteCost = v ?? 1; policyDirty = true; }),
                    ),
                    DropdownButtonFormField<int>(
                      key: ValueKey('minutes-$policyRevision'),
                      initialValue: screenDailyMinutes,
                      decoration: const InputDecoration(
                        labelText: 'Daily minutes limit',
                      ),
                      items: [
                        for (final i in {
                          15,
                          30,
                          60,
                          120,
                          screenDailyMinutes,
                        }.toList()..sort())
                          DropdownMenuItem(value: i, child: Text('$i')),
                      ],
                      onChanged: busy ? null : (v) => setState(() { screenDailyMinutes = v ?? 120; policyDirty = true; }),
                    ),
                    FilledButton(
                      onPressed:
                          busy || selectedChild == null || !screenPoliciesLoaded
                          ? null
                          : () {
                              run(() async {
                                await client.rpc('onestep_set_screen_policy', {
                                  'child': selectedChild,
                                  'allow_unlock': screenUnlockAllowed,
                                  'minute_cost': screenMinuteCost,
                                  'day_minutes': screenDailyMinutes,
                                });
                                policyDirty = false;
                                await refresh();
                                setState(
                                  () => message = 'Parent policy saved.',
                                );
                              });
                            },
                      child: const Text('Save child policy'),
                    ),
                  ]),
                if (children.isNotEmpty)
                  panel('Offline parent authorization', [
                    DropdownButtonFormField<String>(
                      key: ValueKey('parent-$selectedChild'),
                      initialValue: selectedChild,
                      decoration: const InputDecoration(
                        labelText: 'Child account',
                      ),
                      items: children
                          .map(
                            (c) => DropdownMenuItem(
                              value: c['child_id'] as String,
                              child: Text(c['nickname'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (id) => setState(() {
                              selectPolicy(id);
                            }),
                    ),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () {
                              run(() async {
                                final pin = ParentPin.generate();
                                final verifier = await ParentPin.verifier(pin);
                                await client.rpc('onestep_set_parent_pin', {
                                  'child': selectedChild,
                                  'verifier': verifier,
                                });
                                await FamilyClient.vault.write(
                                  key:
                                      'family.parentPin.${client.userID}.$selectedChild',
                                  value: pin,
                                );
                                setState(() {
                                  message =
                                      'Parent code: $pin. Keep it private. Open Kids online and refresh once to cache the verifier before relying on offline unlock.';
                                });
                              });
                            },
                      child: const Text('Generate or rotate parent code'),
                    ),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () {
                              run(() async {
                                final pin = await FamilyClient.vault.read(
                                  key:
                                      'family.parentPin.${client.userID}.$selectedChild',
                                );
                                setState(() {
                                  message = pin == null
                                      ? 'No code saved on this parent device.'
                                      : 'Parent code: $pin';
                                });
                              });
                            },
                      child: const Text('Show saved code offline'),
                    ),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () {
                              run(() async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text(
                                      'Unlink this child account?',
                                    ),
                                    content: const Text(
                                      'Only the parent can do this. Existing points and task history remain stored.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(c, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('Unlink'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true) return;
                                await client.rpc('onestep_unlink_child', {
                                  'child': selectedChild,
                                });
                                selectedChild = null;
                                await refresh();
                              });
                            },
                      child: const Text('Parent: unlink child'),
                    ),
                    const Text(
                      'Offline codes authorize actions inside OneStep, not OS Screen Time. Signing out does not unlink the family on the server. App deletion, device reset, or a compromised device cannot be prevented by this beta. Rotated codes reach Kids on its next successful refresh.',
                    ),
                  ]),
              ],
              if (effectiveRole == 'kids' && children.isEmpty)
                panel('Join your family', [
                  TextField(
                    controller: invite,
                    decoration: const InputDecoration(
                      labelText: 'Parent’s invitation code',
                    ),
                    autocorrect: false,
                  ),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () {
                            run(() async {
                              await client.rpc('onestep_accept_family_invite', {
                                'invite_code': invite.text.trim(),
                                'child_name': nickname.text.trim(),
                              });
                              invite.clear();
                              await refresh();
                            });
                          },
                    child: const Text('Join family'),
                  ),
                ]),
              if (effectiveRole != 'bank')
                panel(
                  effectiveRole == 'parent'
                      ? 'Tasks and approvals'
                      : 'Your family tasks',
                  [
                    if (tasks.isEmpty) const Text('No assigned tasks yet.'),
                    for (final task in tasks)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(task['title'] as String),
                        subtitle: Text(
                          '${task['points']} points · ${task['status']}',
                        ),
                        trailing:
                            effectiveRole == 'parent' &&
                                task['status'] == 'submitted'
                            ? Wrap(
                                children: [
                                  IconButton(
                                    tooltip: 'Return for another try',
                                    onPressed: busy
                                        ? null
                                        : () {
                                            run(() async {
                                              await client.rpc(
                                                'onestep_review_family_task',
                                                {
                                                  'task': task['id'],
                                                  'approve': false,
                                                },
                                              );
                                              await refresh();
                                            });
                                          },
                                    icon: const Icon(Icons.undo),
                                  ),
                                  IconButton(
                                    tooltip: 'Approve points',
                                    onPressed: busy
                                        ? null
                                        : () {
                                            run(() async {
                                              await client.rpc(
                                                'onestep_review_family_task',
                                                {
                                                  'task': task['id'],
                                                  'approve': true,
                                                },
                                              );
                                              await refresh();
                                            });
                                          },
                                    icon: const Icon(
                                      Icons.check_circle_outline,
                                    ),
                                  ),
                                ],
                              )
                            : effectiveRole == 'kids' &&
                                  task['status'] == 'assigned'
                            ? TextButton(
                                onPressed: busy
                                    ? null
                                    : () {
                                        run(() async {
                                          await client.rpc(
                                            'onestep_submit_family_task',
                                            {'task': task['id']},
                                          );
                                          await refresh();
                                        });
                                      },
                                child: const Text('Ask for approval'),
                              )
                            : null,
                      ),
                  ],
                ),
              if (client.signedIn)
                panel('Transactions', [
                  if (ledger.isEmpty)
                    const Text(
                      'No activity yet. Earn points by completing eligible tasks.',
                    ),
                  for (final entry in ledger) BankTransaction(entry:entry),
                  const Text(
                    'Balances are calculated by the service. Updates refresh automatically while this screen is open, or when you tap Refresh.',
                  ),
                ]),
              if (effectiveRole == 'bank')
                panel('Where to use your account', [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use the separate Bank app'),
                    subtitle: const Text(
                      'Preference for this device. Both views use the same account and ledger; this does not move or duplicate points.',
                    ),
                    value: externalBank,
                    onChanged: busy
                        ? null
                        : (value) {
                            run(() async {
                              await FamilyClient.vault.write(
                                key: 'family.externalBank',
                                value: '$value',
                              );
                              setState(() {
                                externalBank = value;
                              });
                            });
                          },
                  ),
                  if (externalBank)
                    const Text(
                      'Open OneStep Bank and sign in to this same account. The built-in section remains available so you are never locked out.',
                    ),
                ]),
              if (client.accountKind != 'kids')
                panel('Public profile', [
                  TextField(
                    controller: publicName,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                    ),
                  ),
                  TextField(
                    controller: handle,
                    decoration: const InputDecoration(labelText: 'Handle'),
                    autocorrect: false,
                  ),
                  SwitchListTile(
                    title: const Text('Opt in to leaderboard'),
                    value: optIn,
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            optIn = v;
                          }),
                  ),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () {
                            run(() async {
                              await client.rpc('onestep_update_profile', {
                                'profile_name': publicName.text,
                                'profile_handle': handle.text,
                                'opt_in': optIn,
                              });
                              setState(() {
                                message = 'Public profile saved.';
                              });
                            });
                          },
                    child: const Text('Save public profile'),
                  ),
                ]),
              if (client.accountKind != 'kids')
                panel('This week: opt-in rankings', [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'tasks', label: Text('Tasks done')),
                      ButtonSegment(
                        value: 'points',
                        label: Text('Points earned'),
                      ),
                    ],
                    selected: {rankingMetric},
                    onSelectionChanged: (v) {
                      setState(() => rankingMetric = v.first);
                      run(refresh);
                    },
                  ),
                  const Text(
                    'Eligible self-reported tasks. Max20 tasks /500 earned points per UTC day; 0–100 per task. Duplicate-title, age and rate filters apply. Admin credits do not count.',
                  ),
                  if (rankings.isEmpty)
                    const Text(
                      'No public scores yet. Joining the leaderboard is optional.',
                    ),
                  for (var index = 0; index < rankings.length; index++)
                    ListTile(
                      leading: Text('#${index + 1}'),
                      title: Text(rankings[index]['display_name'] as String),
                      subtitle: Text('@${rankings[index]['handle'] ?? ''}'),
                      trailing: Text(
                        '${rankings[index][rankingMetric == 'tasks' ? 'completed_tasks' : 'earned_points']} ${rankingMetric == 'tasks' ? 'tasks' : 'points'}',
                      ),
                    ),
                  const Text(
                    'Kids accounts are excluded by the service, regardless of client settings.',
                  ),
                ]),
              if (bankTab == 4) if (client.accountKind == 'kids' || client.accountKind == null)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () {
                          run(childSignOut);
                        },
                  child: const Text('Parent-authorized device sign-out'),
                )
              else
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () {
                          run(() async {
                            await client.signOut();
                            setState(() {
                              admin = false; screenPoliciesLoaded = false; bankTab = 0;
      tasks = [];
                              children = [];
                              families = [];
                              ledger = [];
                              balance = 0;
                              hasSnapshot = false;
                              lastSync = '';
                              rankings = [];
                              publicName.clear();
                              handle.clear();
                            });
                          });
                        },
                  child: const Text('Sign out of this device'),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

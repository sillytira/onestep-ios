import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'model.dart';

class Planner extends ChangeNotifier {
  Json state;
  final Directory directory;
  final Alerts alerts;
  Future<void> _writes = Future.value();
  String? warning;
  Planner(this.state, this.directory, this.alerts);

  static Future<Planner> load() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final file = File('${dir.path}/planner.json');
    final previous = File('${dir.path}/planner.previous.json');
    // A corrupt primary file never silently resets the planner.
    final state = await file.exists()
        ? decodeTransfer(await file.readAsString())
        : await previous.exists()
        ? decodeTransfer(await previous.readAsString())
        : emptyState();
    final planner = Planner(state, dir, Alerts());
    try {
      await planner.alerts.initialize();
      await planner.alerts.apply(state);
    } catch (e) {
      planner.warning = 'Planner loaded; notifications unavailable: $e';
    }
    return planner;
  }

  Future<void> save(Json next) {
    final result = Completer<void>();
    _writes = _writes.then((_) async {
      try {
        validateState(next);
        final file = File('${directory.path}/planner.json');
        final temp = File('${directory.path}/planner.pending.json');
        await temp.writeAsString(encodeTransfer(next), flush: true);
        if (await file.exists()) {
          final previous = File('${directory.path}/planner.previous.json');
          if (await previous.exists()) await previous.delete();
          await file.rename(previous.path);
        }
        await temp.rename(file.path);
        state = clone(next);
        notifyListeners();
        result.complete();
        try {
          await alerts.apply(state);
        } catch (e) {
          warning = 'Saved, but reminders need attention: $e';
          notifyListeners();
        }
      } catch (e, trace) {
        result.completeError(e, trace);
      }
    });
    return result.future;
  }

  Future<void> replace(Json incoming) async {
    final recovery = Directory('${directory.path}/Recovery');
    await recovery.create(recursive: true);
    await File(
      '${recovery.path}/before-import-${DateTime.now().microsecondsSinceEpoch}.json',
    ).writeAsString(encodeTransfer(state), flush: true);
    final next = clone(incoming)..remove('focusSession');
    await save(next);
  }

  Future<void> snooze(Json item) async {
    final next = clone(state);
    next.remove('focusSession');
    final mins = next['preferences']?['snoozeMinutes'] as int? ?? 10;
    var date = DateTime.now().add(Duration(minutes: mins));
    if (item['kind'] == 'task') {
      for (final t in next['tasks'] as List) {
        if (t['id'] == item['sourceID']) t['snoozedUntil'] = stamp(date);
      }
    } else {
      final now = DateTime.now();
      final midnight = DateTime(
        now.year,
        now.month,
        now.day + 1,
      ).subtract(const Duration(seconds: 1));
      if (date.isAfter(midnight)) date = midnight;
      final days = rows(next, 'days')
        ..removeWhere(
          (r) => r['stepID'] == item['sourceID'] && r['day'] == dayKey(now),
        );
      days.add({
        'stepID': item['sourceID'],
        'day': dayKey(now),
        'title': item['title'],
        'snoozedUntil': stamp(date),
        'updatedAt': stamp(now),
      });
      next['days'] = days;
    }
    await save(next);
  }
}

class Alerts {
  final plugin = FlutterLocalNotificationsPlugin();
  Timer? _desktop;
  final Set<String> _delivered = {};
  Json _state = emptyState();
  bool ready = false;
  Future<void> initialize() async {
    tzdata.initializeTimeZones();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        linux: LinuxInitializationSettings(defaultActionName: 'Open OneStep'),
        windows: WindowsInitializationSettings(
          appName: 'OneStep',
          appUserModelId: 'meow.tira.onestep',
          guid: '95ecea8a-baa2-4f50-9a3a-f6608825f704',
        ),
      ),
    );
    ready = true;
    if (!Platform.isAndroid)
      _desktop = Timer.periodic(const Duration(seconds: 15), (_) async {
        final now = DateTime.now();
        for (final alert in reminders(
          _state,
          now.subtract(const Duration(seconds: 15)),
        )) {
          if (!alert.at.isAfter(now) && _delivered.add(alert.key)) {
            try {
              await plugin.show(
                idOf(alert.key),
                alert.title,
                alert.timer
                    ? 'Your focus time is up.'
                    : 'One thing at a time. Open OneStep when ready.',
                const NotificationDetails(
                  linux: LinuxNotificationDetails(),
                  windows: WindowsNotificationDetails(),
                ),
              );
            } catch (_) {
              /* UI states desktop support is conditional. */
            }
          }
        }
      });
  }

  int idOf(String value) => value.codeUnits.fold<int>(
    2166136261,
    (h, c) => ((h ^ c) * 16777619) & 0x7fffffff,
  );
  Future<void> permissions() async {
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    await apply(_state);
  }

  Future<void> apply(Json state) async {
    _state = clone(state);
    if (!ready || !Platform.isAndroid) return;
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final exact = await android?.canScheduleExactNotifications() ?? false;
    final plan = reminders(state, DateTime.now());
    await plugin.cancelAll();
    for (final alert in plan) {
      await plugin.zonedSchedule(
        idOf(alert.key),
        alert.title,
        alert.timer
            ? 'Your focus time is up.'
            : 'One thing at a time. Open OneStep when ready.',
        tz.TZDateTime.from(alert.at.toUtc(), tz.UTC),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'onestep_reminders',
            'OneStep reminders',
            channelDescription: 'Tasks, daily routines, and focus timers',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  void dispose() {
    _desktop?.cancel();
  }
}

bool privateIPv4(String value) {
  final parts = value.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null || p < 0 || p > 255))
    return false;
  return parts[0] == 10 ||
      parts[0] == 192 && parts[1] == 168 ||
      parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31;
}

class LanTransfer {
  HttpServer? _server;
  Timer? _expiry;
  String invitation = '';
  static Future<List<String>> addresses() async =>
      (await NetworkInterface.list(type: InternetAddressType.IPv4))
          .expand((i) => i.addresses)
          .map((a) => a.address)
          .where(privateIPv4)
          .toList();
  Future<String> start(Json state, String host) async {
    await stop();
    if (!privateIPv4(host))
      throw const FormatException('Choose this device’s private IPv4 address.');
    final aes = AesGcm.with256bits();
    final key = await aes.newSecretKey();
    final raw = await key.extractBytes();
    final token = (await Sha256().hash(
      raw,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final clear = utf8.encode(encodeTransfer(state));
    if (clear.length > 8 * 1024 * 1024)
      throw const FormatException('Snapshot is too large.');
    final box = await aes.encrypt(clear, secretKey: key);
    final bytes = <int>[...box.nonce, ...box.cipherText, ...box.mac.bytes];
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    _expiry = Timer(const Duration(minutes: 10), () {
      stop();
    });
    server.listen((request) async {
      try {
        request.response.headers.set('Cache-Control', 'no-store');
        if (request.method != 'GET' ||
            request.uri.path != '/snapshot' ||
            request.headers.value('Authorization') != 'Bearer $token') {
          request.response.statusCode = 403;
        } else {
          request.response.headers.contentType = ContentType.binary;
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
        }
        await request.response.close().timeout(const Duration(seconds: 15));
      } catch (_) {
        request.response.close();
      }
    });
    invitation =
        'onestep-transfer://$host:${server.port}/#${base64Encode(raw)}';
    return invitation;
  }

  Future<void> stop() async {
    _expiry?.cancel();
    _expiry = null;
    invitation = '';
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  static Future<Json> receive(String code) async {
    final uri = Uri.parse(code.trim());
    final raw = base64Decode(uri.fragment);
    if (uri.scheme != 'onestep-transfer' ||
        !privateIPv4(uri.host) ||
        !uri.hasPort ||
        raw.length != 32)
      throw const FormatException('Invalid pairing code.');
    final token = (await Sha256().hash(
      raw,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(
        Uri(scheme: 'http', host: uri.host, port: uri.port, path: '/snapshot'),
      );
      request.followRedirects = false;
      request.headers.set('Authorization', 'Bearer $token');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != 200 ||
          response.contentLength > 8 * 1024 * 1024 + 28)
        throw const FormatException('Sender refused transfer or code expired.');
      final builder = BytesBuilder();
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        builder.add(chunk);
        if (builder.length > 8 * 1024 * 1024 + 28)
          throw const FormatException('Transfer is too large.');
      }
      final bytes = builder.takeBytes();
      if (bytes.length < 28)
        throw const FormatException('Invalid encrypted data.');
      final box = SecretBox(
        bytes.sublist(12, bytes.length - 16),
        nonce: bytes.sublist(0, 12),
        mac: Mac(bytes.sublist(bytes.length - 16)),
      );
      final clear = await AesGcm.with256bits().decrypt(
        box,
        secretKey: SecretKey(raw),
      );
      return decodeTransfer(utf8.decode(clear));
    } finally {
      client.close(force: true);
    }
  }
}

Future<Json> authRequest(
  String project,
  String publicKey,
  String path,
  Json body,
) async {
  final base = Uri.parse(project);
  bool allowedKey = publicKey.startsWith('sb_publishable_');
  try {
    final parts = publicKey.split('.');
    if (parts.length == 3)
      allowedKey =
          (jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map)['role'] ==
          'anon';
  } catch (_) {
    /* Not a legacy public JWT. */
  }
  if (base.scheme != 'https' ||
      !base.host.endsWith('.supabase.co') ||
      !allowedKey)
    throw const FormatException(
      'Use your Supabase HTTPS URL and publishable key, never a secret or service-role key.',
    );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.postUrl(base.resolve('/auth/v1/$path'));
    request.followRedirects = false;
    request.headers.set('apikey', publicKey);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 20));
    final text = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw const FormatException(
        'Sign-in failed. Check your project configuration, email code, and service availability.',
      );
    return jsonDecode(text) as Json;
  } finally {
    client.close(force: true);
  }
}

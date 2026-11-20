import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onestep/android_experience.dart';
import 'package:onestep/family.dart';
import 'package:onestep/model.dart';
import 'package:onestep/services.dart';

class XPClient extends FamilyClient {
  final bool online;
  XPClient(this.online);
  @override
  Future<void> load() async {
    session = {
      'access_token': 'synthetic',
      'expires_at': 4102444800,
      'user': {'id': '66666666-6666-4666-8666-666666666666'},
    };
    accountKind = 'normal';
  }

  @override
  Future<dynamic> rpc(
    String name, [
    Map<String, dynamic> args = const {},
  ]) async {
    if (!online) throw const FormatException('Simulated unavailable service');
    return {'version': 6, 'xp_total': 120, 'xp_today': 30};
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('More destinations remain reachable with large text', (
    tester,
  ) async {
    var notes = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(1.6),
          ),
          child: Scaffold(
            body: AndroidMore(
              notes: () => notes = true,
              history: () {},
              library: () {},
              settings: () {},
              backups: () {},
              wifi: () {},
              xp: () {},
              family: () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Notes'));
    expect(notes, true);
    await tester.scrollUntilVisible(find.text('Reminders and settings'), 250);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'XP distinguishes service-confirmed total from pending offline completions',
    (tester) async {
      final planner = Planner(emptyState(), Directory.systemTemp, Alerts());
      await tester.pumpWidget(
        MaterialApp(
          home: XPBetaPage(
            planner: planner,
            client: XPClient(true),
            account: () async {},
            rankings: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('120 XP'), findsOneWidget);
      expect(find.text('30 / 1,000 XP today'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: XPBetaPage(
            planner: planner,
            client: XPClient(false),
            account: () async {},
            rankings: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('120 XP'), findsNothing);
      expect(find.textContaining('beta service upgrade'), findsOneWidget);
    },
  );
  testWidgets('Reduced motion disables both directions of tab animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: PageMotion(identity: 0, child: Text('Now'))),
        ),
      ),
    );
    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, Duration.zero);
    expect(switcher.reverseDuration, Duration.zero);
  });
}

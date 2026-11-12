import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onestep/family.dart';
import 'package:onestep/connection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'An old manual connection cannot strand the built-in account service',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'family.connection': jsonEncode({
          'url': 'https://legacy.invalid',
          'key': 'obsolete-client-key',
        }),
      });
      final client = FamilyClient();
      await client.load();
      expect(client.project, serviceURL);
      expect(client.publicKey, servicePublishableKey);
    },
  );
  test(
    'Concurrent requests rotate a session once and all use the new token',
    () async {
      // This test talks only to its loopback fixture, not Flutter's default HTTP-400 stub.
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      FlutterSecureStorage.setMockInitialValues({});
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var rotations = 0, protectedRequests = 0;
      late FamilyClient client;
      final serving = server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/auth/v1/token') {
          rotations++;
          await request.drain<void>();
          await Future<void>.delayed(const Duration(milliseconds: 30));
          request.response.write(
            jsonEncode({
              'access_token': 'synthetic-new-token',
              'refresh_token': 'synthetic-rotated-token',
              'expires_in': 3600,
              'user': {'id': 'synthetic-user'},
            }),
          );
        } else {
          expect(
            request.headers.value('Authorization'),
            'Bearer synthetic-new-token',
          );
          protectedRequests++;
          if (request.uri.path.endsWith('/switch')) {
            client.session = Map<String, dynamic>.from(client.session!)
              ..['user'] = {'id': 'another-synthetic-user'};
          }
          request.response.write('[]');
        }
        await request.response.close();
      });
      addTearDown(serving.cancel);
      client = FamilyClient()
        ..project = 'http://127.0.0.1:${server.port}'
        ..publicKey = 'synthetic-test-public-client'
        ..session = {
          'access_token': 'synthetic-old-token',
          'refresh_token': 'synthetic-refresh',
          'expires_at': 0,
          'user': {'id': 'synthetic-user'},
        };
      await Future.wait(List.generate(8, (_) => client.list('test')));
      expect(rotations, 1);
      expect(protectedRequests, 8);
      expect(client.signedIn, true);
      await expectLater(client.list('switch'), throwsA(isA<FormatException>()));
    },
  );
}

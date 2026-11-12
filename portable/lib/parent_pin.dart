import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'model.dart';

class ParentPin {
  static String generate() {
    final random = Random.secure();
    return List.generate(10, (_) => random.nextInt(10)).join();
  }

  static Future<Json> verifier(String pin, {List<int>? salt}) async {
    if (!RegExp(r'^\d{10}$').hasMatch(pin))
      throw const FormatException('Enter the 10-digit parent code.');
    final random = Random.secure();
    final bytes = salt ?? List.generate(16, (_) => random.nextInt(256));
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 120000,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: bytes);
    return {
      'algorithm': 'pbkdf2-sha256',
      'iterations': 120000,
      'salt': base64Encode(bytes),
      'hash': base64Encode(await key.extractBytes()),
    };
  }

  static Future<bool> matches(String pin, Json expected) async {
    if (expected['algorithm'] != 'pbkdf2-sha256' ||
        expected['iterations'] != 120000)
      return false;
    try {
      final salt = base64Decode(expected['salt'] as String);
      final wanted = base64Decode(expected['hash'] as String);
      if (salt.length != 16 || wanted.length != 32) return false;
      final actual = base64Decode(
        (await verifier(pin, salt: salt))['hash'] as String,
      );
      var difference = 0;
      for (var i = 0; i < 32; i++) {
        difference |= actual[i] ^ wanted[i];
      }
      return difference == 0;
    } catch (_) {
      return false;
    }
  }
}

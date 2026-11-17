import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'model.dart';

/// Interoperable with Apple's CryptoKit/CommonCrypto implementation.
class BackupCrypto {
  static const iterations = 600000;
  static const maximum = 8 * 1024 * 1024;
  static final _aes = AesGcm.with256bits();
  static Future<SecretKey> _key(String password, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  static List<int> _random(int n) { final random=Random.secure(); return List.generate(n, (_) => random.nextInt(256)); }
  static Future<String> seal(String clear, String password) async {
    if (password.length < 12 || utf8.encode(password).length > 1024) throw const FormatException('Use a passphrase of 12–1,024 characters.');
    if (utf8.encode(clear).length > maximum) throw const FormatException('Backup is too large.');
    final salt=_random(16), nonce=_random(12);
    final box=await _aes.encrypt(utf8.encode(clear), secretKey:await _key(password,salt),nonce:nonce,aad:utf8.encode('OneStepEncrypted:1'));
    return jsonEncode({'format':'OneStepEncrypted','version':1,'kdf':'PBKDF2-HMAC-SHA256','iterations':iterations,'salt':base64Encode(salt),'nonce':base64Encode(nonce),'data':base64Encode([...box.cipherText,...box.mac.bytes])});
  }
  static Future<String> open(String envelope,String password) async {
    try {
      if(utf8.encode(envelope).length>12*1024*1024 || utf8.encode(password).length>1024) throw const FormatException();
      final e=jsonDecode(envelope) as Map;
      if(e['format']!='OneStepEncrypted'||e['version']!=1||e['kdf']!='PBKDF2-HMAC-SHA256'||e['iterations']!=iterations)throw const FormatException();
      final salt=base64Decode(e['salt'] as String),nonce=base64Decode(e['nonce'] as String),data=base64Decode(e['data'] as String);
      if(salt.length!=16||nonce.length!=12||data.length<16||data.length>maximum+16)throw const FormatException();
      final clear=await _aes.decrypt(SecretBox(data.sublist(0,data.length-16),nonce:nonce,mac:Mac(data.sublist(data.length-16))),secretKey:await _key(password,salt),aad:utf8.encode('OneStepEncrypted:1'));
      return utf8.decode(clear);
    } catch (_) {throw const FormatException('Wrong passphrase or damaged encrypted backup. Nothing was replaced.');}
  }
  static bool encrypted(String text) {try{return (jsonDecode(text) as Map)['format']=='OneStepEncrypted';}catch(_){return false;}}
  static Future<Json> decode(String text,String password) async => decodeTransfer(encrypted(text)?await open(text,password):text);
}

import 'dart:convert';
import 'model.dart';

const reconnectMessage = 'Your sign-in session expired. Open Bank → Account → Reconnect this account. Your planner, pending XP and family link are kept.';
class ReconnectRequired extends FormatException {
  const ReconnectRequired([super.message = reconnectMessage]);
  @override String toString() => message;
}
class AccountServiceFailure extends FormatException {
  final int status;
  final String? code;
  AccountServiceFailure(this.status, this.code, String message) : super(message);
  @override String toString() => message;
  bool get invalidRefresh {
    final value = '${code ?? ''} $message'.toLowerCase();
    return [400,401,403].contains(status) &&
      (value.contains('refresh token') || value.contains('refresh_token') ||
       value.contains('invalid_grant') || value.contains('session_not_found'));
  }
}
class SessionRules {
  static bool token(dynamic value) => value is String && value.trim().isNotEmpty;
  static Json claims(Json? session) {
    try {
      final access = session?['access_token'];
      if (access is! String || access.length > 16384) return {};
      final parts = access.split('.');
      if (parts.length != 3) return {};
      return Map<String,dynamic>.from(jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map);
    } catch (_) { return {}; }
  }
  // JWT hints restore display identity/expiry only; the service still verifies access.
  static String? userID(Json? session) {
    final user = session?['user'];
    final id = user is Map ? user['id'] : null;
    return token(id) ? id as String : token(claims(session)['sub']) ? claims(session)['sub'] as String : null;
  }
  static String? email(Json? session) {
    final user = session?['user'];
    final email = user is Map ? user['email'] : null;
    return token(email) ? email as String : token(claims(session)['email']) ? claims(session)['email'] as String : null;
  }
  static double expiry(Json? session) {
    final value = session?['expires_at'] ?? claims(session)['exp'];
    return value is num && value.isFinite ? value.toDouble() : 0;
  }
  static Json validated(dynamic response) {
    if (response is! Map || !token(response['access_token']) ||
        !token(response['refresh_token']) || response['user'] is! Map ||
        !token((response['user'] as Map)['id'])) {
      throw const ReconnectRequired('Sign-in returned an incomplete session. Try signing in again; no saved account or planner data was replaced.');
    }
    final next = Map<String,dynamic>.from(response);
    if (expiry(next) <= 0) {
      final seconds = next['expires_in'];
      next['expires_at'] = DateTime.now().millisecondsSinceEpoch / 1000 +
          (seconds is num && seconds.isFinite && seconds > 0 ? seconds : 3600);
    } else { next['expires_at'] = expiry(next); }
    return next;
  }
}

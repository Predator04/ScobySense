import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'errors.dart';

class CognitoConfig {
  static const region = 'us-east-1';
  static const userPoolId = 'us-east-1_kgPju5Qgj';
  static const clientId = '79579brug2p0sqmajgd4i44v9e';
}

class AuthTokens {
  final String idToken;
  final String accessToken;
  final String refreshToken;
  AuthTokens(this.idToken, this.accessToken, this.refreshToken);
}

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _kId = 'cognito_id';
  static const _kAccess = 'cognito_access';
  static const _kRefresh = 'cognito_refresh';
  static const _kEmail = 'cognito_email';

  final _pool =
      CognitoUserPool(CognitoConfig.userPoolId, CognitoConfig.clientId);

  Future<AuthTokens> login(String email, String password) async {
    try {
      final user = CognitoUser(email, _pool);
      final details =
          AuthenticationDetails(username: email, password: password);
      final session = await user.authenticateUser(details);
      if (session == null) {
        throw const AuthFailure('Authentication returned no session.');
      }
      final id = session.getIdToken().getJwtToken();
      final access = session.getAccessToken().getJwtToken();
      final refresh = session.getRefreshToken()?.getToken();
      if (id == null || access == null || refresh == null) {
        throw const AuthFailure('Cognito session missing a token.');
      }
      final tokens = AuthTokens(id, access, refresh);
      await _save(email, tokens);
      return tokens;
    } on KombuFailure {
      rethrow;
    } on CognitoClientException catch (e) {
      final msg = e.message ?? e.code ?? 'Sign-in failed.';
      throw AuthFailure(_prettyCognito(e.code, msg), e);
    } catch (e) {
      final text = e.toString().toLowerCase();
      if (text.contains('socketexception') ||
          text.contains('failed host lookup') ||
          text.contains('network is unreachable') ||
          text.contains('clientexception')) {
        throw NetworkFailure('Can\'t reach the sign-in server.', e);
      }
      throw AuthFailure(e.toString(), e);
    }
  }

  String _prettyCognito(String? code, String fallback) {
    switch (code) {
      case 'NotAuthorizedException':
        return 'Email or password is incorrect.';
      case 'UserNotFoundException':
        return 'No account found for that email.';
      case 'UserNotConfirmedException':
        return 'Account not confirmed. Check email for a verification link.';
      case 'PasswordResetRequiredException':
        return 'Password reset required. Reset in the official app first.';
      case 'TooManyRequestsException':
      case 'LimitExceededException':
        return 'Too many attempts. Try again in a minute.';
      default:
        return fallback;
    }
  }

  Future<AuthTokens?> currentTokens({bool refreshIfExpired = true}) async {
    final id = await _storage.read(key: _kId);
    final access = await _storage.read(key: _kAccess);
    final refresh = await _storage.read(key: _kRefresh);
    if (id == null || access == null || refresh == null) return null;
    final tokens = AuthTokens(id, access, refresh);
    if (!refreshIfExpired) return tokens;
    if (_isExpiringSoon(id)) {
      try {
        return await refreshSession();
      } on AuthFailure {
        return null;
      }
    }
    return tokens;
  }

  Future<AuthTokens> refreshSession() async {
    final email = await _storage.read(key: _kEmail);
    final refresh = await _storage.read(key: _kRefresh);
    if (email == null || refresh == null) {
      throw const AuthFailure('Session expired. Please sign in again.');
    }
    try {
      final user = CognitoUser(email, _pool);
      final session = await user.refreshSession(CognitoRefreshToken(refresh));
      if (session == null) {
        throw const AuthFailure('Refresh returned no session.');
      }
      final id = session.getIdToken().getJwtToken()!;
      final access = session.getAccessToken().getJwtToken()!;
      final newRefresh = session.getRefreshToken()?.getToken() ?? refresh;
      final tokens = AuthTokens(id, access, newRefresh);
      await _save(email, tokens);
      return tokens;
    } on KombuFailure {
      rethrow;
    } on CognitoClientException catch (e) {
      throw AuthFailure(_prettyCognito(e.code, e.message ?? 'Refresh failed.'),
          e);
    } catch (e) {
      throw AuthFailure('Could not refresh session.', e);
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: _kId);
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kEmail);
  }

  Future<void> _save(String email, AuthTokens t) async {
    await _storage.write(key: _kEmail, value: email);
    await _storage.write(key: _kId, value: t.idToken);
    await _storage.write(key: _kAccess, value: t.accessToken);
    await _storage.write(key: _kRefresh, value: t.refreshToken);
  }

  bool _isExpiringSoon(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length < 2) return true;
      final payload = _decodeB64Url(parts[1]);
      final match = RegExp(r'"exp"\s*:\s*(\d+)').firstMatch(payload);
      if (match == null) return true;
      final exp = int.parse(match.group(1)!);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return exp - now < 60;
    } catch (_) {
      return true;
    }
  }

  String _decodeB64Url(String s) {
    var p = s.replaceAll('-', '+').replaceAll('_', '/');
    switch (p.length % 4) {
      case 2:
        p += '==';
        break;
      case 3:
        p += '=';
        break;
    }
    return String.fromCharCodes(
      Uri.parse('data:application/octet-stream;base64,$p')
          .data!
          .contentAsBytes(),
    );
  }
}

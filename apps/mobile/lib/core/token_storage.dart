import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists JWT access + refresh tokens in SharedPreferences. Good enough for
/// v1; later we'll move to flutter_secure_storage for keychain/keystore.
class TokenStorage {
  TokenStorage(this._prefs);

  static const _accessKey = 'pp.access_token';
  static const _refreshKey = 'pp.refresh_token';

  final SharedPreferences _prefs;

  String? get accessToken => _prefs.getString(_accessKey);
  String? get refreshToken => _prefs.getString(_refreshKey);
  bool get isAuthenticated => accessToken != null;

  Future<void> save({required String access, required String refresh}) async {
    await _prefs.setString(_accessKey, access);
    await _prefs.setString(_refreshKey, refresh);
  }

  Future<void> clear() async {
    await _prefs.remove(_accessKey);
    await _prefs.remove(_refreshKey);
  }
}

final tokenStorageProvider = FutureProvider<TokenStorage>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return TokenStorage(prefs);
});

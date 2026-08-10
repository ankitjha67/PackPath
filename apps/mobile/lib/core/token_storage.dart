import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists JWT access + refresh tokens in the platform secure enclave
/// (Keychain on iOS, EncryptedSharedPreferences/Keystore on Android) via
/// flutter_secure_storage.
///
/// The tokens are also cached in memory so the synchronous getters used by
/// the Dio interceptor and the live-trip provider keep working — secure
/// storage is async-only. Call [open] once at startup; it hydrates the cache
/// and migrates any tokens left in the old plaintext SharedPreferences store.
class TokenStorage {
  TokenStorage._(this._secure, {String? access, String? refresh})
      : _access = access,
        _refresh = refresh;

  static const _accessKey = 'pp.access_token';
  static const _refreshKey = 'pp.refresh_token';

  final FlutterSecureStorage _secure;
  String? _access;
  String? _refresh;

  String? get accessToken => _access;
  String? get refreshToken => _refresh;
  bool get isAuthenticated => _access != null;

  static Future<TokenStorage> open(SharedPreferences prefs) async {
    const secure = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    var access = await secure.read(key: _accessKey);
    var refresh = await secure.read(key: _refreshKey);

    // One-time migration off the pre-existing plaintext SharedPreferences.
    final legacyAccess = prefs.getString(_accessKey);
    final legacyRefresh = prefs.getString(_refreshKey);
    if (legacyAccess != null || legacyRefresh != null) {
      if (access == null && legacyAccess != null) {
        await secure.write(key: _accessKey, value: legacyAccess);
        access = legacyAccess;
      }
      if (refresh == null && legacyRefresh != null) {
        await secure.write(key: _refreshKey, value: legacyRefresh);
        refresh = legacyRefresh;
      }
      await prefs.remove(_accessKey);
      await prefs.remove(_refreshKey);
    }

    return TokenStorage._(secure, access: access, refresh: refresh);
  }

  Future<void> save({required String access, required String refresh}) async {
    _access = access;
    _refresh = refresh;
    await _secure.write(key: _accessKey, value: access);
    await _secure.write(key: _refreshKey, value: refresh);
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    await _secure.delete(key: _accessKey);
    await _secure.delete(key: _refreshKey);
  }
}

final tokenStorageProvider = FutureProvider<TokenStorage>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return TokenStorage.open(prefs);
});

/// Synchronous handle to the eagerly-opened [TokenStorage]. Overridden in
/// `main.dart`; lets code that must run on the first synchronous build (e.g.
/// the live-trip provider on a cold-start deep link) read tokens without an
/// async gap.
final tokenStorageSyncProvider = Provider<TokenStorage>(
  (ref) => throw UnimplementedError(
    'tokenStorageSyncProvider must be overridden in main.dart',
  ),
);

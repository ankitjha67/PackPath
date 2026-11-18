import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';

/// The backend a self-hoster points this app at. One APK works for everyone:
/// the server URL is set in-app (Settings) and persisted, falling back to the
/// compile-time default in [Env] when unset.
class ServerConfig {
  const ServerConfig(this.httpBase, this.wsBase);

  /// e.g. https://packpath.example.com (no trailing slash).
  final String httpBase;

  /// Derived WebSocket base, e.g. wss://packpath.example.com.
  final String wsBase;

  static ServerConfig fromBase(String base) {
    final http = base.trim().replaceAll(RegExp(r'/+$'), '');
    final ws =
        http.replaceFirst(RegExp(r'^http'), 'ws'); // http->ws, https->wss
    return ServerConfig(http, ws);
  }

  /// The configuration currently in effect, kept in sync by
  /// [ServerConfigController]. For call sites without a Riverpod `ref`
  /// (e.g. media-URL helpers inside message bubbles); everything else
  /// should watch [serverConfigProvider].
  static ServerConfig active = ServerConfig.fromBase(Env.apiBaseUrl);
}

const _kServerUrl = 'pp.server_url';

class ServerConfigController extends StateNotifier<ServerConfig> {
  ServerConfigController(this._prefs) : super(_load(_prefs)) {
    ServerConfig.active = state;
  }

  final SharedPreferences _prefs;

  static ServerConfig _load(SharedPreferences p) {
    final v = p.getString(_kServerUrl);
    return ServerConfig.fromBase(
      (v != null && v.trim().isNotEmpty) ? v : Env.apiBaseUrl,
    );
  }

  /// The user-set URL, or null when falling back to the built-in default.
  String? get configured => _prefs.getString(_kServerUrl);

  Future<void> setUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      await reset();
      return;
    }
    await _prefs.setString(_kServerUrl, trimmed);
    state = ServerConfig.fromBase(trimmed);
    ServerConfig.active = state;
  }

  Future<void> reset() async {
    await _prefs.remove(_kServerUrl);
    state = ServerConfig.fromBase(Env.apiBaseUrl);
    ServerConfig.active = state;
  }
}

/// Overridden in main.dart with the bootstrapped SharedPreferences instance.
final serverConfigProvider =
    StateNotifierProvider<ServerConfigController, ServerConfig>((ref) {
  throw UnimplementedError(
    'serverConfigProvider must be overridden in main.dart',
  );
});

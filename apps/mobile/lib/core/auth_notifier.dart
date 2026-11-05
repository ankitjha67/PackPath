import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'token_storage.dart';

/// Small [Listenable] the router subscribes to via `refreshListenable`, so a
/// login or logout immediately re-evaluates the redirect guard. Auth state
/// itself lives in [TokenStorage]; this only fans out change notifications.
class AuthNotifier extends ChangeNotifier {
  AuthNotifier(this._storage);

  final TokenStorage _storage;

  bool get isLoggedIn => _storage.isAuthenticated;

  /// Poke listeners after tokens are written or cleared.
  void notifyChanged() => notifyListeners();
}

/// Overridden in `main.dart` with an instance backed by the eagerly-loaded
/// [TokenStorage], so the router can read auth state synchronously.
final authNotifierProvider = Provider<AuthNotifier>(
  (ref) => throw UnimplementedError(
    'authNotifierProvider must be overridden in main.dart',
  ),
);

// Verifies TokenStorage serializes save()/clear() and honours the save
// validity guard, so a token refresh that completes after a logout or account
// switch cannot restore the previous account's tokens.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packpath/core/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> store;

  setUp(() {
    store = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map?) ?? const {};
      switch (call.method) {
        case 'read':
          return store[args['key'] as String];
        case 'write':
          store[args['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          store.remove(args['key'] as String);
          return null;
        case 'readAll':
          return Map<String, String>.from(store);
        case 'deleteAll':
          store.clear();
          return null;
        case 'containsKey':
          return store.containsKey(args['key'] as String);
      }
      return null;
    });
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<TokenStorage> openStorage() async =>
      TokenStorage.open(await SharedPreferences.getInstance());

  test('save then clear leaves no tokens', () async {
    final storage = await openStorage();
    await storage.save(access: 'a', refresh: 'r');
    expect(storage.accessToken, 'a');
    await storage.clear();
    expect(storage.accessToken, isNull);
    expect(store.values, isEmpty);
  });

  test('save with a false validity guard is skipped', () async {
    final storage = await openStorage();
    await storage.save(access: 'a', refresh: 'r', isValid: () => false);
    expect(storage.accessToken, isNull);
    expect(store, isEmpty);
  });

  test('a stale refresh racing a logout clear cannot restore tokens', () async {
    final storage = await openStorage();
    await storage.save(access: 'a', refresh: 'r'); // account A is signed in

    // A refresh bound to the pre-logout session queues its save; a logout
    // clear follows. The save's guard reflects that the session changed, so
    // the queued write must be skipped and the store must end up empty.
    var loggedOut = false;
    final staleSave = storage.save(
      access: 'a2',
      refresh: 'r2',
      isValid: () => !loggedOut,
    );
    loggedOut = true;
    final clear = storage.clear();

    await Future.wait([staleSave, clear]);

    expect(storage.accessToken, isNull,
        reason: 'a stale refresh must not restore tokens after logout');
    expect(store.values, isEmpty);
  });
}

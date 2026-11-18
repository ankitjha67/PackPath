// Verifies the api_client session-isolation guards: a request stamped in an
// earlier session (before a logout / account switch bumped the epoch) is
// rejected in onRequest instead of being sent with the new account's token,
// and a 401 that arrives after the session changed leaves the new session's
// auth state alone (no spurious forceLogout).
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packpath/core/api_client.dart';
import 'package:packpath/core/auth_notifier.dart';
import 'package:packpath/core/server_config.dart';
import 'package:packpath/core/session.dart';
import 'package:packpath/core/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers requests with a canned status after an optional [gate] future,
/// recording what actually reached the wire.
class _GatedAdapter implements HttpClientAdapter {
  _GatedAdapter(this.statusCode, {this.gate});
  final int statusCode;
  final Future<void>? gate;
  final sent = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    if (gate != null) await gate;
    return ResponseBody.fromString('{}', statusCode,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });
  }

  @override
  void close({bool force = false}) {}
}

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
      }
      return null;
    });
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<(ProviderContainer, TokenStorage)> buildContainer() async {
    final prefs = await SharedPreferences.getInstance();
    final storage = await TokenStorage.open(prefs);
    final container = ProviderContainer(overrides: [
      serverConfigProvider.overrideWith(
        (ref) => ServerConfigController(prefs),
      ),
      tokenStorageProvider.overrideWith((ref) async => storage),
      tokenStorageSyncProvider.overrideWithValue(storage),
      authNotifierProvider.overrideWithValue(AuthNotifier(storage)),
    ]);
    addTearDown(container.dispose);
    return (container, storage);
  }

  test('a request stamped in an old session is rejected before sending',
      () async {
    final (container, storage) = await buildContainer();
    await storage.save(access: 'tokenA', refresh: 'refreshA');
    final dio = await container.read(apiClientProvider.future);
    final adapter = _GatedAdapter(200);
    dio.httpClientAdapter = adapter;

    // Stamp the request with the current epoch, then switch sessions before
    // it reaches onRequest — as a delayed retry would.
    final opts = RequestOptions(path: '/trips')
      ..extra['__pp_epoch'] = container.read(sessionEpochProvider);
    container.read(sessionEpochProvider.notifier).state++;

    await expectLater(dio.fetch<dynamic>(opts), throwsA(isA<DioException>()));
    expect(adapter.sent, isEmpty,
        reason: 'a stale-session request must never reach the network');
  });

  test('a 401 arriving after a session switch does not log the new one out',
      () async {
    final (container, storage) = await buildContainer();
    await storage.save(access: 'tokenA', refresh: 'refreshA');
    final dio = await container.read(apiClientProvider.future);
    final gate = Completer<void>();
    final adapter = _GatedAdapter(401, gate: gate.future);
    dio.httpClientAdapter = adapter;

    // Fire the request; it is stamped with epoch 0 and held at the gate.
    final future = dio.get<dynamic>('/trips');
    while (adapter.sent.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    // Now the session changes (account B logs in) before the 401 lands.
    container.read(sessionEpochProvider.notifier).state++;
    await storage.save(access: 'tokenB', refresh: 'refreshB');
    gate.complete();

    await expectLater(future, throwsA(isA<DioException>()));
    expect(storage.accessToken, 'tokenB',
        reason: "the stale 401 must not clear the new session's tokens");
    expect(container.read(sessionEpochProvider), 1,
        reason: 'forceLogout must not fire for a stale session');
  });
}

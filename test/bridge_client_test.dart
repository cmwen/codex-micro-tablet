import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codex_micro_tablet/bridge_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Keep protocol assertions below real BridgeClient serialization/parsing while
// replacing socket I/O. flutter_tester's socket binding may stall under WSL.
class _Headers implements HttpHeaders {
  final values = <String, Object>{};
  @override
  ContentType? contentType;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, this.body);
  @override
  final int statusCode;
  final String body;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(utf8.encode(body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.method, this.uri, this.respond);
  @override
  final String method;
  @override
  final Uri uri;
  final _Response Function(_Request) respond;
  final body = <int>[];
  @override
  final _Headers headers = _Headers();
  @override
  bool followRedirects = true;
  @override
  void add(List<int> data) => body.addAll(data);
  @override
  Future<HttpClientResponse> close() async => respond(this);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.respond);
  final _Response Function(_Request) respond;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(method, url, respond);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Http extends HttpOverrides {
  _Http(this.respond);
  final _Response Function(_Request) respond;
  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client(respond);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = MethodChannel('codex_micro/hid');
  Map<String, dynamic>? saved;
  HttpOverrides? previousOverrides;
  setUp(() {
    previousOverrides = HttpOverrides.current;
    saved = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, (call) async {
          if (call.method == 'loadBridgeSettings') return saved;
          if (call.method == 'saveBridgeSettings') {
            saved = Map<String, dynamic>.from(call.arguments as Map);
          }
          return null;
        });
  });
  tearDown(() {
    HttpOverrides.global = previousOverrides;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, null);
  });

  test('URL validation limits plaintext tokens to local networks', () {
    for (final url in [
      'http://192.168.1.2:8765',
      'http://10.1.2.3',
      'http://172.16.0.2',
      'http://mac.local:8765',
      'http://[fd00::1]',
      'https://bridge.example.com',
    ]) {
      expect(BridgeClient.validateUrl(url).host, isNotEmpty);
    }
    for (final url in [
      'http://example.com',
      'http://172.32.0.2',
      'http://192.168.0.2.example.com',
      'http://user:pass@localhost',
      'http://localhost/?token=secret',
      'file:///etc/passwd',
      'http://localhost/v1/status',
      'http://localhost/#secret',
    ]) {
      expect(() => BridgeClient.validateUrl(url), throwsFormatException);
    }
  });

  test(
    'authenticated status and explicit text match existing bridge contract',
    () async {
      final client = BridgeClient(pollInterval: const Duration(days: 1));
      addTearDown(client.dispose);
      Map<String, dynamic>? submission;
      var posts = 0;
      HttpOverrides.global = _Http((request) {
        expect(request.headers.values['x-monitor-key'], 'private-test-key');
        expect(request.uri.host, '127.0.0.1');
        expect(request.uri.port, 8765);
        expect(request.followRedirects, isFalse);
        if (request.method == 'GET') {
          expect(request.uri.path, '/v1/status');
          return _Response(
            200,
            jsonEncode({
              'integration': 'connected',
              'agents': <dynamic>[],
              'codex': {
                'usage': {
                  'five_hour': {'used_percent': 29},
                },
              },
            }),
          );
        }
        expect(request.method, 'POST');
        expect(request.uri.path, '/v1/commands/text');
        expect(request.headers.contentType?.mimeType, 'application/json');
        posts++;
        submission =
            jsonDecode(utf8.decode(request.body)) as Map<String, dynamic>;
        return _Response(
          200,
          '{"ok":true,"action":"queued","job_id":"test-job"}',
        );
      });
      await client.configure('http://127.0.0.1:8765', 'private-test-key');
      expect(client.connected, isTrue);
      expect(saved?['token'], 'private-test-key');
      final reply = await client.sendText(
        '  Check build  ',
        agentId: 'thread-1',
      );
      expect(reply['job_id'], 'test-job');
      expect(submission?['text'], 'Check build');
      expect(submission?['agent_id'], 'thread-1');
      expect(submission?['request_id'], startsWith('tablet-'));
      expect(posts, 1);
      expect(client.busy, isFalse);
      await client.configure('', '');
      expect(client.snapshot, isNull);
      expect(client.connected, isFalse);
    },
  );

  test(
    'redirect responses never trigger another authenticated request',
    () async {
      var requests = 0;
      HttpOverrides.global = _Http((request) {
        requests++;
        expect(request.followRedirects, isFalse);
        return _Response(302, '');
      });
      final client = BridgeClient(pollInterval: const Duration(days: 1));
      addTearDown(client.dispose);
      await client.configure('http://127.0.0.1:8765', 'secret');
      expect(requests, 1);
      expect(client.connected, isFalse);
      expect(client.error, contains('302'));
      expect(client.error, isNot(contains('secret')));
    },
  );

  test('failed explicit submissions are never retried', () async {
    var posts = 0;
    HttpOverrides.global = _Http((request) {
      if (request.method == 'POST') {
        posts++;
        return _Response(503, '');
      }
      return _Response(
        200,
        '{"integration":"connected","agents":[],"codex":{}}',
      );
    });
    final client = BridgeClient(pollInterval: const Duration(days: 1));
    addTearDown(client.dispose);
    await client.configure('http://127.0.0.1:8765', 'test');
    await expectLater(
      client.sendText('Build it'),
      throwsA(isA<BridgeException>()),
    );
    expect(posts, 1);
    expect(client.busy, isFalse);
  });

  test('unauthorized and malformed status never appear connected', () async {
    var unauthorized = true;
    HttpOverrides.global = _Http(
      (request) => unauthorized
          ? _Response(401, '')
          : _Response(200, '{"unexpected":true}'),
    );
    final client = BridgeClient(pollInterval: const Duration(days: 1));
    addTearDown(client.dispose);
    await client.configure('http://127.0.0.1:8765', 'secret');
    expect(client.error, contains('authentication'));
    unauthorized = false;
    await client.refresh();
    expect(client.connected, isFalse);
    expect(client.snapshot, isNull);
  });

  test('read-only Agent Deck source is verified before it is saved', () async {
    final paths = <String>[];
    HttpOverrides.global = _Http((request) {
      paths.add(request.uri.path);
      // A discovered read-only origin never receives the bridge monitor key.
      expect(request.headers.values.containsKey('x-monitor-key'), isFalse);
      expect(request.uri.scheme, 'https');
      expect(request.uri.host, 'agent-deck-lan.home.test');
      expect(request.uri.port, 8444);
      expect(request.followRedirects, isFalse);
      return _Response(
        200,
        jsonEncode({
          'integration': 'connected',
          'harnesses': [
            {
              'id': 'codex',
              'integration': 'connected',
              'agents': [
                {'id': 'codex:a', 'name': 'Fix build', 'status': 'running'},
              ],
              'usage': {
                'quota': {
                  'five_hour': {'used_percent': 30, 'resets_at': 1794721384},
                },
              },
            },
            {'id': 't3code', 'integration': 'degraded', 'agents': <dynamic>[]},
          ],
        }),
      );
    });
    final client = BridgeClient(pollInterval: const Duration(days: 1));
    addTearDown(client.dispose);
    await client.configureReadOnly('https://agent-deck-lan.home.test:8444');
    // Probe first, then the adopted source reads the same read-only endpoint.
    expect(paths, ['/api/snapshot', '/api/snapshot']);
    expect(saved?['kind'], 'agent-deck');
    expect(saved?['token'], '');
    expect(saved?['url'], 'https://agent-deck-lan.home.test:8444');
    expect(client.readOnly, isTrue);
    expect(client.sourceLabel, 'Agent Deck');
    expect(client.connected, isTrue);
    expect((client.snapshot?['agents'] as List).length, 1);
    expect(client.snapshot?['codex']['usage']['five_hour']['used_percent'], 30);
    await expectLater(
      client.sendText('Build it'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('read-only'),
        ),
      ),
    );
    expect(paths, ['/api/snapshot', '/api/snapshot']);
  });

  test(
    'read-only sources refuse plaintext and incompatible endpoints',
    () async {
      var paths = <String>[];
      var status = 200;
      HttpOverrides.global = _Http((request) {
        paths.add(request.uri.path);
        if (status != 200) return _Response(status, '');
        // A legacy bridge response is not the Agent Deck contract.
        return _Response(
          200,
          '{"integration":"connected","agents":[],"codex":{}}',
        );
      });
      final client = BridgeClient(pollInterval: const Duration(days: 1));
      addTearDown(client.dispose);
      await expectLater(
        client.configureReadOnly('http://192.168.1.17:8082'),
        throwsFormatException,
      );
      expect(paths, isEmpty);
      expect(saved, isNull);

      await expectLater(
        client.configureReadOnly('https://agent-deck-lan.home.test:8444'),
        throwsFormatException,
      );
      expect(saved, isNull);
      expect(client.baseUrl, isEmpty);

      paths = <String>[];
      status = 404;
      await expectLater(
        client.configureReadOnly('https://agent-deck-lan.home.test:8444'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('does not serve the monitor API'),
          ),
        ),
      );
      expect(saved, isNull);
    },
  );

  test('a saved read-only source never reloads a monitor key', () async {
    saved = {
      'url': 'https://agent-deck-lan.home.test:8444',
      'token': 'stale-key',
      'kind': 'agent-deck',
    };
    HttpOverrides.global = _Http((request) {
      expect(request.headers.values.containsKey('x-monitor-key'), isFalse);
      return _Response(
        200,
        jsonEncode({
          'harnesses': [
            {'id': 'codex', 'integration': 'connected', 'agents': <dynamic>[]},
            {'id': 't3code', 'integration': 'connected', 'agents': <dynamic>[]},
          ],
        }),
      );
    });
    final client = BridgeClient(pollInterval: const Duration(days: 1));
    addTearDown(client.dispose);
    await client.load();
    expect(client.kind, MonitorSourceKind.agentDeck);
    expect(client.token, isEmpty);
    expect(client.connected, isTrue);
  });

  test('legacy saved settings still load as the bridge contract', () async {
    saved = {'url': 'http://127.0.0.1:8765', 'token': 'legacy-key'};
    HttpOverrides.global = _Http((request) {
      expect(request.headers.values['x-monitor-key'], 'legacy-key');
      expect(request.uri.path, '/v1/status');
      return _Response(
        200,
        '{"integration":"connected","agents":[],"codex":{}}',
      );
    });
    final client = BridgeClient(pollInterval: const Duration(days: 1));
    addTearDown(client.dispose);
    await client.load();
    expect(client.kind, MonitorSourceKind.bridge);
    expect(client.readOnly, isFalse);
    expect(client.connected, isTrue);
  });
}

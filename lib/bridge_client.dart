import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'agent_deck_snapshot.dart';

/// Which read-only monitor contract a client speaks.
///
/// The legacy FNK0104B bridge (`GET /v1/status`, `X-Monitor-Key`) and the Agent Deck LAN
/// contract (`GET /api/snapshot`, HTTPS only, no key) are separate APIs. Each kind uses
/// its own endpoint and its own validating parser, and only the bridge kind carries a
/// credential.
enum MonitorSourceKind {
  bridge('bridge', 'Bridge'),
  agentDeck('agent-deck', 'Agent Deck');

  const MonitorSourceKind(this.wire, this.label);
  final String wire, label;

  static MonitorSourceKind parse(Object? value) =>
      values.firstWhere((kind) => kind.wire == value, orElse: () => bridge);
}

/// Client for the existing FNK0104B monitor-server HTTP contract.
/// Reads retry periodically; explicit submissions are never retried.
class BridgeClient extends ChangeNotifier {
  BridgeClient({this.pollInterval = const Duration(seconds: 5)});
  static const _storage = MethodChannel('codex_micro/hid');
  final Duration pollInterval;
  String baseUrl = '', token = '', status = 'Not configured', error = '';
  bool connected = false, busy = false;
  Map<String, dynamic>? snapshot;
  DateTime? lastUpdated;
  MonitorSourceKind kind = MonitorSourceKind.bridge;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;
  int? _reading;

  /// True when the active source cannot send prompts or controls.
  bool get readOnly => kind == MonitorSourceKind.agentDeck;
  String get sourceLabel => kind.label;

  static Uri validateUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        'Enter a bridge origin, such as http://192.168.1.20:8765',
      );
    }
    if (uri.scheme == 'http' && !_localHost(uri.host)) {
      throw const FormatException(
        'Use HTTPS for remote hosts. HTTP is supported for private LAN addresses and .local names.',
      );
    }
    return uri.replace(path: '');
  }

  /// A read-only Agent Deck origin must be verified TLS; there is no plaintext or
  /// redirect entry point for this source.
  static Uri validateReadOnlyUrl(String value) {
    final uri = validateUrl(value);
    if (uri.scheme != 'https') {
      throw const FormatException(
        'A read-only monitor source requires an HTTPS origin.',
      );
    }
    return uri;
  }

  static bool _localHost(String host) {
    if (host == 'localhost' || host.endsWith('.local')) return true;
    final ip = InternetAddress.tryParse(host);
    if (ip == null) return false;
    if (ip.isLoopback) return true;
    final bytes = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4) {
      return bytes[0] == 10 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (bytes[0] == 169 && bytes[1] == 254);
    }
    return (bytes[0] & 0xfe) == 0xfc ||
        (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
  }

  Future<void> load() async {
    final saved = await _storage.invokeMapMethod<String, dynamic>(
      'loadBridgeSettings',
    );
    if (_disposed || saved == null || (saved['url'] as String? ?? '').isEmpty) {
      return;
    }
    final kind = MonitorSourceKind.parse(saved['kind']);
    _activate(
      saved['url'] as String,
      kind == MonitorSourceKind.bridge ? saved['token'] as String? ?? '' : '',
      kind,
    );
    await refresh();
  }

  Future<void> configure(String url, String key) async {
    final origin = url.trim().isEmpty ? '' : validateUrl(url).toString();
    if (key.contains('\r') || key.contains('\n')) {
      throw const FormatException('The bridge token must be a single line.');
    }
    await _storage.invokeMethod<void>('saveBridgeSettings', {
      'url': origin,
      'token': key,
      'kind': MonitorSourceKind.bridge.wire,
    });
    if (_disposed) return;
    _activate(origin, key, MonitorSourceKind.bridge);
    if (origin.isNotEmpty) await refresh();
  }

  /// Verifies a discovered read-only origin, then saves it. Nothing is persisted
  /// unless the endpoint answers with the Agent Deck contract over verified TLS.
  Future<void> configureReadOnly(String origin) async {
    final uri = validateReadOnlyUrl(origin);
    await _probe(uri);
    await _storage.invokeMethod<void>('saveBridgeSettings', {
      'url': uri.toString(),
      'token': '',
      'kind': MonitorSourceKind.agentDeck.wire,
    });
    if (_disposed) return;
    _activate(uri.toString(), '', MonitorSourceKind.agentDeck);
    await refresh();
  }

  /// Fetches and validates a candidate without saving or adopting it.
  Future<void> _probe(Uri origin) async {
    try {
      final data = await _request(
        origin,
        '',
        'GET',
        _pathFor(MonitorSourceKind.agentDeck),
      );
      normalizeAgentDeckSnapshot(data);
    } on FormatException {
      throw const FormatException(
        'That service does not expose the Agent Deck read-only API.',
      );
    } on BridgeException catch (error) {
      throw FormatException(error.message);
    } catch (_) {
      throw const FormatException(
        'Cannot reach that service over HTTPS. Check the home network and its certificate.',
      );
    }
  }

  String _pathFor(MonitorSourceKind value) =>
      value == MonitorSourceKind.agentDeck ? '/api/snapshot' : '/v1/status';

  void _activate(String url, String key, MonitorSourceKind source) {
    // Validate persisted settings too; no unrestricted plaintext destinations.
    kind = source;
    baseUrl = url.isEmpty
        ? ''
        : (source == MonitorSourceKind.agentDeck
              ? validateReadOnlyUrl(url).toString()
              : validateUrl(url).toString());
    token = source == MonitorSourceKind.bridge ? key : '';
    ++_generation;
    _timer?.cancel();
    snapshot = null;
    connected = false;
    busy = false;
    error = '';
    status = url.isEmpty ? 'Not configured' : 'Connecting';
    if (url.isNotEmpty) {
      _timer = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
    }
    _emit();
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    if (_disposed || baseUrl.isEmpty || _reading == _generation) return;
    final generation = _generation;
    final source = kind;
    _reading = generation;
    try {
      final origin = validateUrl(baseUrl);
      final data = await _request(
        origin,
        source == MonitorSourceKind.bridge ? token : '',
        'GET',
        _pathFor(source),
      );
      if (_disposed || generation != _generation) return;
      if (source == MonitorSourceKind.bridge) {
        if (data['codex'] is! Map ||
            data['agents'] is! List ||
            data['integration'] is! String) {
          throw const FormatException(
            'Bridge response does not match the monitor status API.',
          );
        }
        snapshot = _validateSnapshot(data);
      } else {
        snapshot = normalizeAgentDeckSnapshot(data);
      }
      lastUpdated = DateTime.now();
      final integration = snapshot!['integration'];
      connected = integration == 'connected';
      status = connected
          ? 'Connected'
          : '${source.label} ${integration ?? 'unknown'}';
      error = connected
          ? ''
          : source == MonitorSourceKind.bridge
          ? 'The bridge cannot fully observe Codex. Check the bridge on your Mac.'
          : 'Agent Deck reports limited observation. Check its desktop service.';
    } catch (e) {
      if (_disposed || generation != _generation) return;
      connected = false;
      snapshot = null;
      status = 'Offline';
      error = _safeError(e);
    } finally {
      if (_reading == generation) _reading = null;
      if (!_disposed && generation == _generation) _emit();
    }
  }

  static Map<String, dynamic> _validateSnapshot(Map<String, dynamic> data) {
    final codex = data['codex'] as Map;
    final usage = codex['usage'];
    if (usage != null && usage is! Map) {
      throw const FormatException('Invalid quota data.');
    }
    if (usage is Map) {
      for (final name in ['five_hour', 'weekly']) {
        final bucket = usage[name];
        if (bucket == null) continue;
        if (bucket is! Map) {
          throw const FormatException('Invalid quota bucket.');
        }
        final used = bucket['used_percent'], reset = bucket['resets_at'];
        if ((used != null &&
                (used is! num || !used.isFinite || used < 0 || used > 100)) ||
            (reset != null &&
                (reset is! num ||
                    !reset.isFinite ||
                    reset < 0 ||
                    reset > 8640000000000))) {
          throw const FormatException('Invalid quota values.');
        }
      }
    }
    final ids = <String>{};
    for (final agent in data['agents'] as List) {
      if (agent is! Map ||
          agent['id'] is! String ||
          (agent['id'] as String).isEmpty ||
          !ids.add(agent['id'] as String)) {
        throw const FormatException('Invalid or duplicate thread identity.');
      }
    }
    return data;
  }

  Future<Map<String, dynamic>> sendText(String text, {String? agentId}) async {
    // Prompt delivery exists only on the bridge contract; a read-only source must
    // never be treated as an interchangeable transport.
    if (readOnly) {
      throw StateError(
        'This source is read-only. Connect the Codex bridge to send messages.',
      );
    }
    if (_disposed || baseUrl.isEmpty || !connected) {
      throw StateError('Connect the bridge before sending a message.');
    }
    if (busy) throw StateError('A message is already being submitted.');
    if (text.trim().isEmpty || utf8.encode(text).length > 24000) {
      throw const FormatException('Enter a message of at most 24 KB.');
    }
    final generation = _generation;
    busy = true;
    _emit();
    try {
      final result = await _request(
        validateUrl(baseUrl),
        token,
        'POST',
        '/v1/commands/text',
        {
          'text': text.trim(),
          if (agentId != null) 'agent_id': agentId,
          'request_id': 'tablet-${DateTime.now().microsecondsSinceEpoch}',
        },
      );
      if (result['ok'] == false || result['error'] != null) {
        throw const BridgeException(
          'The bridge rejected the message. Check Codex before trying again.',
        );
      }
      return result;
    } catch (e) {
      throw BridgeException(
        '${_safeError(e)} Check Codex before resending; delivery may have completed.',
      );
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        _emit();
      }
    }
  }

  Future<Map<String, dynamic>> _request(
    Uri origin,
    String key,
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      return await (() async {
        final request = await client.openUrl(
          method,
          origin.replace(path: path),
        );
        request.followRedirects =
            false; // Never forward a private key to a redirect.
        if (key.isNotEmpty) request.headers.set('X-Monitor-Key', key);
        if (data != null) {
          request.headers.contentType = ContentType.json;
          request.add(utf8.encode(jsonEncode(data)));
        }
        final response = await request.close();
        if (response.statusCode != 200) {
          throw BridgeException(switch (response.statusCode) {
            401 => 'Bridge authentication failed. Check the shared token.',
            404 => 'That address does not serve the monitor API.',
            409 => 'Codex needs attention in the desktop app.',
            503 => 'The bridge cannot reach its Codex app-server.',
            _ => 'Monitor service returned HTTP ${response.statusCode}.',
          });
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 256 * 1024) {
            throw const FormatException('Bridge response is too large.');
          }
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Invalid bridge JSON.');
        }
        return decoded;
      })().timeout(const Duration(seconds: 12));
    } finally {
      client.close(force: true);
    }
  }

  String _safeError(Object error) {
    if (error is BridgeException) return error.message;
    if (error is TimeoutException) return 'Monitor request timed out.';
    if (error is FormatException) return error.message;
    if (readOnly) {
      return 'Cannot reach Agent Deck. Check the home network and its HTTPS origin.';
    }
    return 'Cannot reach the bridge. Check its address, Wi-Fi and shared token.';
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    token = '';
    super.dispose();
  }
}

class BridgeException implements Exception {
  const BridgeException(this.message);
  final String message;
  @override
  String toString() => message;
}

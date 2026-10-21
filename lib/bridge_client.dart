import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;
  int? _reading;

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
    _activate(saved['url'] as String, saved['token'] as String? ?? '');
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
    });
    if (_disposed) return;
    _activate(origin, key);
    if (origin.isNotEmpty) await refresh();
  }

  void _activate(String url, String key) {
    // Validate persisted settings too; no unrestricted plaintext destinations.
    baseUrl = url.isEmpty ? '' : validateUrl(url).toString();
    token = key;
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
    _reading = generation;
    try {
      final data = await _request('GET', '/v1/status');
      if (_disposed || generation != _generation) return;
      if (data['codex'] is! Map ||
          data['agents'] is! List ||
          data['integration'] is! String) {
        throw const FormatException(
          'Bridge response does not match the monitor status API.',
        );
      }
      snapshot = _validateSnapshot(data);
      lastUpdated = DateTime.now();
      connected = data['integration'] == 'connected';
      status = connected ? 'Connected' : 'Bridge ${data['integration']}';
      error = connected
          ? ''
          : 'The bridge cannot fully observe Codex. Check the bridge on your Mac.';
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
      final result = await _request('POST', '/v1/commands/text', {
        'text': text.trim(),
        if (agentId != null) 'agent_id': agentId,
        'request_id': 'tablet-${DateTime.now().microsecondsSinceEpoch}',
      });
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
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final origin = validateUrl(baseUrl);
    final key = token;
    try {
      return await (() async {
        final request = await client.openUrl(
          method,
          origin.replace(path: path),
        );
        request.followRedirects =
            false; // Never forward a private key to a redirect.
        request.headers.set('X-Monitor-Key', key);
        if (data != null) {
          request.headers.contentType = ContentType.json;
          request.add(utf8.encode(jsonEncode(data)));
        }
        final response = await request.close();
        if (response.statusCode != 200) {
          throw BridgeException(switch (response.statusCode) {
            401 => 'Bridge authentication failed. Check the shared token.',
            409 => 'Codex needs attention in the desktop app.',
            503 => 'The bridge cannot reach its Codex app-server.',
            _ => 'Bridge returned HTTP ${response.statusCode}.',
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

  static String _safeError(Object error) {
    if (error is BridgeException) return error.message;
    if (error is TimeoutException) return 'Bridge request timed out.';
    if (error is FormatException) {
      return 'Bridge response or address is invalid.';
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

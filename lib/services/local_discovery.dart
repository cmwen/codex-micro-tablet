import 'dart:async';

import 'package:flutter/services.dart';

/// A DNS-SD service instance reported by the platform browser.
///
/// Discovery results are untrusted endpoint candidates. Nothing here authenticates a
/// service, and no credential may be sent to one until the user has chosen it and the
/// monitor client has verified its API contract over the verified TLS identity below.
class DiscoveredService {
  const DiscoveredService({
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    required this.attributes,
  });

  final String name;
  final String type;
  final String host;
  final int port;
  final Map<String, String> attributes;

  static const _maxServices = 50;

  /// The public HTTPS origin a service publishes in its TXT record, if it does.
  ///
  /// Browsers cannot browse DNS-SD and this app must not follow a redirect while
  /// holding a key, so only an explicit HTTPS origin is treated as a monitor identity.
  Uri? get httpsOrigin {
    final raw = attributes['https'];
    if (raw == null || raw.length > 2048) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.port == 0) {
      return null;
    }
    return uri.replace(path: '');
  }

  /// True when this instance publishes the read-only Agent Deck LAN origin.
  bool get advertisesAgentDeck => httpsOrigin != null;

  String get address => 'http://$host:$port';

  /// Short, redacted description for an explicit user choice.
  String describe() => advertisesAgentDeck
      ? '$name · ${httpsOrigin!.host}'
      : '$name · $host:$port';

  /// Reason this candidate cannot be used as a monitor source, if any.
  String? get unsupportedReason {
    if (advertisesAgentDeck) return null;
    return 'No HTTPS monitor origin published';
  }

  /// Android 10 reports "._http._tcp" on some builds; the contract form ends in a dot.
  static String _canonicalType(String value) {
    final trimmed = value.trim().replaceFirst(RegExp(r'^\.+'), '');
    return trimmed.endsWith('.') ? trimmed : '$trimmed.';
  }

  static DiscoveredService? parse(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    final type = value['type'];
    final host = value['host'];
    final port = value['port'];
    if (name is! String ||
        name.trim().isEmpty ||
        name.length > 128 ||
        type is! String ||
        !_type.hasMatch(type) ||
        host is! String ||
        !_host.hasMatch(host) ||
        port is! int ||
        port < 1 ||
        port > 65535) {
      return null;
    }
    final attributes = <String, String>{};
    final raw = value['attributes'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final key = entry.key, text = entry.value;
        if (key is! String ||
            !_attributeKey.hasMatch(key) ||
            text is! String ||
            text.length > 255 ||
            text.codeUnits.any((unit) => unit < 0x20 || unit > 0x7e)) {
          continue;
        }
        attributes[key] = text;
      }
    }
    return DiscoveredService(
      name: name.trim(),
      type: _canonicalType(type),
      host: host,
      port: port,
      attributes: Map.unmodifiable(attributes),
    );
  }

  static final _type = RegExp(
    r'^_[a-z0-9](?:[a-z0-9-]{0,13}[a-z0-9])?\._(?:tcp|udp)\.$',
  );
  static final _host = RegExp(r'^[A-Za-z0-9.:\[\]-]{1,64}$');
  static final _attributeKey = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$');
  static int get maxServices => _maxServices;
}

class DiscoveryException implements Exception {
  const DiscoveryException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Bounded one-shot DNS-SD browse through the platform (Android NSD).
///
/// It runs only for an explicit user request, never in the background, and returns
/// candidates without choosing or trusting any of them.
class LocalServiceDiscovery {
  const LocalServiceDiscovery();

  static const channel = MethodChannel('codex_micro/discovery');

  Future<List<DiscoveredService>> discover({
    Duration timeout = const Duration(seconds: 6),
    String serviceType = '_http._tcp.',
  }) async {
    final List<Object?>? raw;
    try {
      raw = await channel.invokeListMethod<Object?>('discover', {
        'serviceType': serviceType,
        'timeoutMs': timeout.inMilliseconds.clamp(1500, 15000),
      });
    } on PlatformException catch (error) {
      throw DiscoveryException(
        error.message ?? 'Local service discovery failed.',
      );
    } on MissingPluginException {
      throw const DiscoveryException(
        'Local service discovery is unavailable on this device.',
      );
    }
    final services = <DiscoveredService>[];
    for (final value in raw ?? const <Object?>[]) {
      final service = DiscoveredService.parse(value);
      if (service == null ||
          services.any(
            (seen) =>
                seen.name == service.name &&
                seen.host == service.host &&
                seen.port == service.port,
          )) {
        continue;
      }
      services.add(service);
      if (services.length == DiscoveredService.maxServices) break;
    }
    services.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return services;
  }

  /// Stops an in-flight browse when the settings dialog closes early.
  Future<void> stop() async {
    try {
      await channel.invokeMethod<void>('stop');
    } on PlatformException {
      // A browse that already ended needs no cancellation.
    } on MissingPluginException {
      // Nothing to stop without the platform browser.
    }
  }
}

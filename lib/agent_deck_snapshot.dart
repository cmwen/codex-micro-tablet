/// Read-only Agent Deck LAN contract (`GET /api/snapshot`).
///
/// Agent Deck is a different application from the FNK0104B monitor bridge. This module
/// validates that contract strictly and normalizes it into the native display model so
/// the existing monitor views can render it; it never falls back to the bridge parser,
/// and it never carries the bridge's shared monitor key.
library;

const _states = {'connected', 'degraded', 'unavailable'};
const _statuses = {
  'running',
  'needs_attention',
  'error',
  'idle',
  'completed',
  'stopped',
  'unknown',
};
const _sources = ['codex', 't3code'];
const _maxResetSeconds = 8640000000000;

String _text(Object? value, int max) => value is String
    ? value.substring(0, value.length > max ? max : value.length)
    : '';

/// Epoch seconds, accepting the numeric bridge form or an ISO-8601 timestamp.
num? _resetAt(Object? value) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    final seconds = parsed.millisecondsSinceEpoch / 1000;
    return seconds >= 0 && seconds <= _maxResetSeconds ? seconds : null;
  }
  if (value is num &&
      value.isFinite &&
      value >= 0 &&
      value <= _maxResetSeconds) {
    return value;
  }
  return null;
}

Map<String, Object?> _window(Object? value) {
  final bucket = value is Map ? value : const {};
  final used = bucket['used_percent'];
  return {
    'used_percent': used is num && used.isFinite && used >= 0 && used <= 100
        ? used
        : null,
    'resets_at': _resetAt(bucket['resets_at']),
  };
}

/// Validates and normalizes an Agent Deck snapshot for the native monitor views.
///
/// Throws [FormatException] when the endpoint does not implement the Agent Deck
/// contract, so an incompatible service is never pointed at the bridge parser.
Map<String, dynamic> normalizeAgentDeckSnapshot(Object? decoded) {
  if (decoded is! Map) {
    throw const FormatException('Agent Deck did not return a JSON object.');
  }
  final harnesses = decoded['harnesses'];
  if (harnesses is! List) {
    throw const FormatException('Agent Deck did not return monitor sources.');
  }
  final rawIntegration = decoded['integration'];
  final integration =
      rawIntegration is String && _states.contains(rawIntegration)
      ? rawIntegration
      : null;
  final agents = <Map<String, dynamic>>[];
  final ids = <String>{};
  final sources = <Map<String, dynamic>>[];
  final usage = <String, dynamic>{};
  var seenSource = false;
  for (final entry in harnesses) {
    if (entry is! Map) continue;
    final id = entry['id'];
    if (id is! String || !_sources.contains(id)) continue;
    seenSource = true;
    final state = entry['integration'];
    final integration = state is String && _states.contains(state)
        ? state
        : 'unavailable';
    final codexUsage = entry['usage'];
    if (id == 'codex' && codexUsage is Map && codexUsage['quota'] is Map) {
      final quota = codexUsage['quota'] as Map;
      usage['five_hour'] = _window(quota['five_hour']);
      usage['weekly'] = _window(quota['weekly']);
    }
    var count = 0;
    final rawAgents = entry['agents'];
    if (rawAgents is List) {
      for (final agent in rawAgents) {
        if (agent is! Map) continue;
        final agentId = agent['id'];
        if (agentId is! String || agentId.isEmpty || agentId.length > 150) {
          continue;
        }
        if (!ids.add(agentId)) continue;
        final status = agent['status'];
        final name = _text(agent['name'], 100);
        agents.add({
          'id': agentId,
          'name': name.isEmpty ? agentId : name,
          'detail': _text(agent['detail'], 240),
          'status': status is String && _statuses.contains(status)
              ? status
              : 'unknown',
          'source': id,
        });
        count++;
      }
    }
    final errors = entry['errors'];
    sources.add({
      'id': id,
      'integration': integration,
      'configured': entry['configured'] == true,
      'observed': count,
      'errors': [
        if (errors is List)
          for (final error in errors.take(5))
            if (error is String) _text(error, 240),
      ],
    });
  }
  if (!seenSource) {
    throw const FormatException('Agent Deck did not report Codex or T3 Code.');
  }
  final resolved =
      integration ??
      (sources.any((source) => source['integration'] == 'connected')
          ? 'connected'
          : 'degraded');
  return {
    'integration': resolved,
    'updated_at': decoded['updated_at'],
    'agents': agents,
    'codex': {'usage': usage.isEmpty ? null : usage},
    'sources': sources,
    'read_only': true,
  };
}

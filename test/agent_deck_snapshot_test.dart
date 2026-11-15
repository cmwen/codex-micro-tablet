import 'package:codex_micro_tablet/agent_deck_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shape returned by Agent Deck's read-only LAN `GET /api/snapshot`.
Map<String, dynamic> snapshot({
  String integration = 'connected',
  Map<String, dynamic>? codex,
  Map<String, dynamic>? t3code,
}) => {
  'integration': integration,
  'updated_at': 1794714760,
  'harnesses': [
    codex ??
        {
          'id': 'codex',
          'configured': true,
          'integration': 'connected',
          'agents': <dynamic>[],
          'total_agents': 0,
          'usage': {
            'scope': 'account_quota',
            'additive': false,
            'quota': {
              'five_hour': {'used_percent': 90, 'resets_at': 1794721384},
              'weekly': {
                'used_percent': 42,
                'resets_at': '2026-11-18T03:03:31.000Z',
              },
            },
          },
          'errors': <dynamic>[],
        },
    t3code ??
        {
          'id': 't3code',
          'configured': true,
          'integration': 'connected',
          'agents': <dynamic>[],
          'usage': null,
          'errors': <dynamic>[],
        },
  ],
};

void main() {
  test('maps Agent Deck sources into the native monitor model', () {
    final value = normalizeAgentDeckSnapshot(
      snapshot(
        codex: {
          'id': 'codex',
          'integration': 'connected',
          'agents': [
            {
              'id': 'codex:a',
              'name': 'Fix build',
              'detail': 'running',
              'status': 'running',
            },
          ],
          'usage': {
            'quota': {
              'five_hour': {'used_percent': 90, 'resets_at': 1794721384},
              'weekly': {
                'used_percent': 42,
                'resets_at': '2026-11-18T03:03:31.000Z',
              },
            },
          },
        },
        t3code: {
          'id': 't3code',
          'integration': 'degraded',
          'agents': [
            {
              'id': 't3code:b',
              'name': 'Review PR',
              'detail': 'failed',
              'status': 'error',
            },
            {'id': 't3code:a', 'status': 'something-new'},
            {'id': 't3code:a', 'status': 'running'},
            {'name': 'no id', 'status': 'running'},
          ],
          'errors': ['History unavailable'],
        },
      ),
    );
    expect(value['read_only'], isTrue);
    expect(value['integration'], 'connected');
    final agents = value['agents'] as List;
    expect(agents.length, 3);
    expect(agents.first, {
      'id': 'codex:a',
      'name': 'Fix build',
      'detail': 'running',
      'status': 'running',
      'source': 'codex',
    });
    final statuses = {for (final agent in agents) agent['id']: agent['status']};
    expect(statuses['t3code:b'], 'error');
    expect(statuses['t3code:a'], 'unknown');
    expect(agents[1]['source'], 't3code');
    final usage = value['codex']['usage'] as Map;
    expect(usage['five_hour']['used_percent'], 90);
    expect(usage['five_hour']['resets_at'], 1794721384);
    expect(usage['weekly']['used_percent'], 42);
    // ISO timestamps are normalized to the bridge's epoch-second form.
    expect(usage['weekly']['resets_at'], 1794971011);
    expect((value['sources'] as List).last['errors'], ['History unavailable']);
  });

  test('keeps uncertainty explicit instead of inventing values', () {
    final value = normalizeAgentDeckSnapshot(
      snapshot(
        integration: 'degraded',
        codex: {
          'id': 'codex',
          'integration': 'degraded',
          'agents': [
            {'id': 'codex:a', 'status': 'unknown'},
            {'id': 'codex:b', 'status': 'running', 'name': 'x' * 400},
          ],
          'usage': {
            'quota': {
              'five_hour': {'used_percent': 130, 'resets_at': -5},
              'weekly': {'used_percent': null},
            },
          },
        },
      ),
    );
    expect(value['integration'], 'degraded');
    final usage = value['codex']['usage'] as Map;
    expect(usage['five_hour']['used_percent'], isNull);
    expect(usage['five_hour']['resets_at'], isNull);
    expect(usage['weekly']['used_percent'], isNull);
    final agents = value['agents'] as List;
    expect(agents.first['status'], 'unknown');
    expect((agents[1]['name'] as String).length, 100);
  });

  test('derives a missing top-level state from the sources', () {
    final value = normalizeAgentDeckSnapshot({
      'harnesses': [
        {'id': 't3code', 'integration': 'unavailable', 'agents': <dynamic>[]},
      ],
    });
    expect(value['integration'], 'degraded');
    expect(value['codex']['usage'], isNull);
  });

  test('rejects endpoints that are not the Agent Deck contract', () {
    for (final value in <Object?>[
      null,
      'ok',
      <String, dynamic>{},
      {'codex': <String, dynamic>{}, 'agents': <dynamic>[]},
      {
        'harnesses': [
          {'id': 'other', 'agents': <dynamic>[]},
        ],
      },
    ]) {
      expect(
        () => normalizeAgentDeckSnapshot(value),
        throwsFormatException,
        reason: '$value',
      );
    }
  });
}

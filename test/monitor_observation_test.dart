import 'package:codex_micro_tablet/bridge_client.dart';
import 'package:codex_micro_tablet/standalone_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 15, 12);
  BridgeClient source(List<Map<String, String>> agents) => BridgeClient()
    ..connected = true
    ..lastUpdated = now
    ..snapshot = {'agents': agents, 'codex': <String, Object>{}};
  test('quiet is scoped to fresh visible bridge chats', () {
    final bridge = source([]);
    expect(MonitorObservation.fromBridge(bridge, now).quiet, isTrue);
    bridge.connected = false;
    expect(MonitorObservation.fromBridge(bridge, now).quiet, isFalse);
    bridge.connected = true;
    expect(
      MonitorObservation.fromBridge(
        bridge,
        now.add(const Duration(seconds: 16)),
      ).quiet,
      isFalse,
    );
    expect(
      MonitorObservation.fromBridge(
        bridge,
        now.subtract(const Duration(seconds: 6)),
      ).quiet,
      isFalse,
    );
    bridge.snapshot = null;
    expect(MonitorObservation.fromBridge(bridge, now).unknown, isTrue);
    bridge.dispose();
  });
  test(
    'running and attention stay independent and unknown cannot imply quiet',
    () {
      final bridge = source([
        {'status': 'working'},
        {'status': 'needs_attention'},
        {'status': 'unknown'},
      ]);
      final observation = MonitorObservation.fromBridge(bridge, now);
      expect(observation.running, 1);
      expect(observation.attention, 1);
      expect(observation.unknown, isTrue);
      expect(observation.quiet, isFalse);
      bridge.dispose();
    },
  );
}

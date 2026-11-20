import 'package:codex_micro_tablet/agent_deck_snapshot.dart';
import 'package:codex_micro_tablet/bridge_client.dart';
import 'package:codex_micro_tablet/hid_service.dart';
import 'package:codex_micro_tablet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MonitorHid extends HidService {
  int initialized = 0;
  int stopped = 0;
  @override
  Future<bool> stop() async {
    stopped++;
    return true;
  }

  @override
  Future<void> initialize() async => initialized++;
  @override
  Future<void> releaseAll() async {}
  @override
  Future<void> refresh() async {}
}

class MonitorBridge extends BridgeClient {
  @override
  Future<void> load() async {}
  @override
  Future<void> refresh() async {}
}

void main() {
  testWidgets('standalone usage distinguishes unavailable from zero', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'standalone_display': true});
    final hid = MonitorHid();
    final bridge = MonitorBridge()
      ..snapshot = {
        'codex': {
          'usage': {
            'five_hour': {'used_percent': 0},
            'weekly': {'used_percent': null},
          },
        },
        'agents': [],
      };
    await tester.pumpWidget(MicroTabletApp(hid: hid, bridge: bridge));
    await tester.pumpAndSettle();
    expect(find.text('0% used'), findsOneWidget);
    expect(find.text('100% remaining'), findsOneWidget);
    expect(find.text('Usage unavailable'), findsOneWidget);
    expect(find.text('Chat activity'), findsOneWidget);
    expect(find.text('All agents idle'), findsNothing);
    expect(
      tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .map((bar) => bar.semanticsLabel),
      [
        '5-hour usage: progress toward reset',
        'Weekly usage: progress toward reset',
      ],
    );
    await tester.pumpWidget(const SizedBox());
    hid.dispose();
    bridge.dispose();
  });

  testWidgets('a partial Agent Deck snapshot still shows live Mac activity', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'standalone_display': true});
    final hid = MonitorHid();
    final bridge = MonitorBridge()
      ..kind = MonitorSourceKind.agentDeck
      ..baseUrl = 'https://deck.example.test'
      ..lastUpdated = DateTime.now()
      ..error = 'Agent Deck reports limited observation.'
      ..snapshot = normalizeAgentDeckSnapshot({
        'integration': 'degraded',
        'harnesses': [
          {
            'id': 'codex',
            'integration': 'degraded',
            'agents': [
              {
                'id': 'codex:companion:sample',
                'name': 'Codex session 037a2d82',
                'status': 'running',
                'detail': 'Desktop companion · test-mac',
              },
            ],
          },
          {'id': 't3code', 'integration': 'unavailable', 'agents': []},
        ],
      });
    await tester.pumpWidget(MicroTabletApp(hid: hid, bridge: bridge));
    await tester.pumpAndSettle();
    expect(find.text('1 running · visible chats'), findsWidgets);
    expect(find.text('Codex session 037a2d82'), findsOneWidget);
    expect(
      find.text('Agent Deck reports limited observation.'),
      findsOneWidget,
    );
    expect(find.text('Activity stale or unavailable'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    hid.dispose();
    bridge.dispose();
  });

  for (final size in [const Size(853, 533), const Size(320, 640)]) {
    testWidgets('Standalone monitor fits $size and shifts', (tester) async {
      SharedPreferences.setMockInitialValues({'standalone_display': true});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final hid = MonitorHid();
      final bridge = MonitorBridge()
        ..baseUrl = 'http://localhost:1234'
        ..status = 'Connected'
        ..connected = true
        ..lastUpdated = DateTime.now()
        ..snapshot = {
          'codex': {
            'usage': {
              'five_hour': {'used_percent': 25},
              'weekly': {'used_percent': 50},
            },
          },
          'agents': [
            {'id': '1', 'name': 'Build app', 'status': 'running'},
          ],
        };
      await tester.pumpWidget(MicroTabletApp(hid: hid, bridge: bridge));
      await tester.pumpAndSettle();
      expect(hid.initialized, 0);
      expect(find.text('25% used'), findsOneWidget);
      expect(find.text('75% remaining'), findsOneWidget);
      expect(find.text('50% remaining'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
      final bars = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .toList();
      expect(bars.map((bar) => bar.value), [0, 0]);
      expect(bars.map((bar) => bar.semanticsValue), [
        'Reset time unavailable',
        'Reset time unavailable',
      ]);
      expect(find.text('Reset time unavailable'), findsNWidgets(2));
      expect(find.byTooltip('Refresh usage'), findsNothing);
      expect(find.byTooltip('Usage bridge settings'), findsNothing);
      expect(find.text('Build app'), findsOneWidget);
      expect(find.text('1 running · visible chats'), findsWidgets);
      expect(find.byTooltip('Connection settings'), findsNothing);
      expect(
        tester
            .widget<Align>(find.byKey(const ValueKey('display-shift')))
            .alignment,
        const Alignment(-1, -1),
      );
      await tester.pump(const Duration(minutes: 1));
      expect(
        tester
            .widget<Align>(find.byKey(const ValueKey('display-shift')))
            .alignment,
        const Alignment(1, -1),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 1));
      expect(
        tester
            .widget<Align>(find.byKey(const ValueKey('display-shift')))
            .alignment,
        const Alignment(1, -1),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(minutes: 1));
      expect(
        tester
            .widget<Align>(find.byKey(const ValueKey('display-shift')))
            .alignment,
        const Alignment(1, 1),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Exit standalone display'));
      await tester.pumpAndSettle();
      expect(hid.initialized, 1);
      await tester.tap(find.byTooltip('Standalone display'));
      await tester.pumpAndSettle();
      expect(hid.stopped, 1);
      expect(find.text('Agent Control'), findsOneWidget);
      await tester.tap(find.byTooltip('Exit standalone display'));
      await tester.pumpAndSettle();
      expect(hid.initialized, 1);
      expect(
        (await SharedPreferences.getInstance()).getBool('standalone_display'),
        false,
      );
      await tester.pumpWidget(const SizedBox());
      hid.dispose();
      bridge.dispose();
    });
  }

  testWidgets('ambient mode keeps a compact date and time', (tester) async {
    SharedPreferences.setMockInitialValues({'standalone_display': true});
    tester.view.physicalSize = const Size(600, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final hid = MonitorHid();
    final bridge = MonitorBridge()
      ..baseUrl = 'http://192.168.1.17:8765'
      ..status = 'Connected'
      ..connected = true
      ..lastUpdated = DateTime.now()
      ..snapshot = {
        'codex': {
          'usage': {
            'five_hour': {'used_percent': 20},
            'weekly': {'used_percent': 40},
          },
        },
        'agents': <dynamic>[],
      };
    await tester.pumpWidget(MicroTabletApp(hid: hid, bridge: bridge));
    await tester.pumpAndSettle();
    expect(find.text('AMBIENT DISPLAY'), findsOneWidget);
    final now = DateTime.now().toLocal();
    final clock =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final localizations = MaterialLocalizations.of(
      tester.element(find.text('AMBIENT DISPLAY')),
    );
    // The ambient entry no longer leads with a full date and a hero clock.
    expect(find.text(localizations.formatFullDate(now)), findsNothing);
    expect(find.text(clock), findsOneWidget);
    expect(find.text(localizations.formatMediumDate(now)), findsOneWidget);
    final clockRow = find.ancestor(
      of: find.text(clock),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(
        of: clockRow.first,
        matching: find.text(localizations.formatMediumDate(now)),
      ),
      findsOneWidget,
    );
    expect(tester.widget<Text>(find.text(clock)).style?.fontSize, lessThan(48));
    expect(
      find.text('Codex account quota · local clock · read-only'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    hid.dispose();
    bridge.dispose();
  });

  testWidgets('a read-only source labels its own contract', (tester) async {
    SharedPreferences.setMockInitialValues({'standalone_display': true});
    final hid = MonitorHid();
    final bridge = MonitorBridge()
      ..kind = MonitorSourceKind.agentDeck
      ..baseUrl = 'https://agent-deck-lan.home.cmwen.dev:8444'
      ..status = 'Connected'
      ..connected = true
      ..lastUpdated = DateTime.now()
      ..snapshot = {
        'integration': 'connected',
        'agents': [
          {
            'id': 't3code:a',
            'name': 'Review PR',
            'status': 'running',
            'source': 't3code',
          },
        ],
        'codex': {'usage': null},
      };
    await tester.pumpWidget(MicroTabletApp(hid: hid, bridge: bridge));
    await tester.pumpAndSettle();
    expect(find.text('AGENT DECK CHATS · 1 visible'), findsOneWidget);
    expect(
      find.text('Read-only Agent Deck snapshot of Codex and T3 Code.'),
      findsOneWidget,
    );
    expect(
      find.text('Read-only Agent Deck source · local clock'),
      findsOneWidget,
    );
    expect(find.text('BRIDGE CHATS · 1 visible'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    hid.dispose();
    bridge.dispose();
  });
}

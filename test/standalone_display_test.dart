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
    expect(
      tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .map((bar) => bar.semanticsLabel),
      ['5-hour usage: 0 percent used', 'Weekly usage: unavailable'],
    );
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
        ..lastUpdated = DateTime(2026)
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
      expect(bars.map((bar) => bar.value), [0.25, 0.5]);
      expect(find.text('Reset time unavailable'), findsNWidgets(2));
      expect(find.byTooltip('Refresh usage'), findsNothing);
      expect(find.byTooltip('Usage bridge settings'), findsNothing);
      expect(find.text('Build app'), findsOneWidget);
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
      expect(find.text('CODEX MONITOR'), findsOneWidget);
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
}

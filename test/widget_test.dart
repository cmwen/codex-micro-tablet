import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_micro_tablet/bridge_client.dart';
import 'package:codex_micro_tablet/hid_service.dart';
import 'package:codex_micro_tablet/main.dart';

class FakeHid extends HidService {
  final keys = <(int, bool)>[];
  int releases = 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> refresh() async {}
  @override
  Future<void> key(int id, bool pressed) async {
    keys.add((id, pressed));
  }

  @override
  Future<void> releaseAll() async {
    releases++;
  }
}

class FakeBridge extends BridgeClient {
  void updateSnapshot(Map<String, dynamic> data) {
    snapshot = data;
    connected = true;
    notifyListeners();
  }

  @override
  Future<void> load() async {}
  @override
  Future<void> refresh() async {}
}

void main() {
  testWidgets(
    'A disappeared selected chat never becomes a new chat submission',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final hid = FakeHid();
      final bridge = FakeBridge()
        ..updateSnapshot({
          'agents': [
            {'id': 'thread-1', 'name': 'Build app', 'status': 'running'},
          ],
          'codex': {},
        });
      await tester.pumpWidget(MicroTabletApp(hid: hid, bridge: bridge));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Build app').last);
      await tester.pumpAndSettle();
      bridge.updateSnapshot({'agents': [], 'codex': {}});
      await tester.pumpAndSettle();
      expect(find.text('Selected chat unavailable'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Send through bridge'),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      hid.dispose();
      bridge.dispose();
    },
  );

  for (final size in [
    const Size(533, 853),
    const Size(853, 533),
    const Size(320, 640),
  ]) {
    testWidgets('Dashboard fits ${size.width} x ${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final hid = FakeHid();
      final bridge = FakeBridge();
      await tester.pumpWidget(MicroTabletApp(hid: hid, bridge: bridge));
      await tester.pumpAndSettle();
      expect(find.text('Your desk, connected.'), findsOneWidget);
      expect(find.text('Agent 6'), findsOneWidget);
      expect(find.text('Connect your Mac to get started'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      hid.dispose();
      bridge.dispose();
    });
  }

  testWidgets('Bluetooth link without discovery leaves controls disabled', (
    tester,
  ) async {
    final hid = FakeHid()..applyState({'connected': true, 'discovered': false});
    final bridge = FakeBridge();
    await tester.pumpWidget(MicroTabletApp(hid: hid, bridge: bridge));
    await tester.pumpAndSettle();
    expect(find.textContaining('Waiting for Micro discovery'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agent-0')));
    expect(hid.keys, isEmpty);
    await tester.pumpWidget(const SizedBox());
    hid.dispose();
    bridge.dispose();
  });

  testWidgets('Touch press, release and cancellation send paired reports', (
    tester,
  ) async {
    final events = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          height: 100,
          child: HoldControl(
            enabled: true,
            onChanged: events.add,
            onTap: () {},
            label: 'Hold',
            icon: Icons.mic,
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldControl)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(events, [true]);
    await gesture.up();
    expect(events, [true, false]);
    final canceled = await tester.startGesture(
      tester.getCenter(find.byType(HoldControl)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await canceled.cancel();
    expect(events, [true, false, true, false]);
  });

  testWidgets('A second pointer cannot release the first held key', (
    tester,
  ) async {
    final events = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: HoldControl(
          enabled: true,
          onChanged: events.add,
          onTap: () {},
          label: 'Hold',
          icon: Icons.mic,
        ),
      ),
    );
    final point = tester.getCenter(find.byType(HoldControl));
    final first = await tester.startGesture(point, pointer: 1);
    await tester.pump(const Duration(milliseconds: 150));
    final second = await tester.startGesture(point, pointer: 2);
    await second.up();
    expect(events, [true]);
    await first.up();
    expect(events, [true, false]);
  });

  testWidgets('Removing a held control releases it', (tester) async {
    final events = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: HoldControl(
          enabled: true,
          onChanged: events.add,
          onTap: () {},
          label: 'Hold',
          icon: Icons.mic,
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldControl)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpWidget(const SizedBox());
    expect(events, [true, false]);
    await gesture.up();
  });

  testWidgets('Scrolling from a command control does not press it', (
    tester,
  ) async {
    final events = <bool>[];
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: controller,
            children: [
              SizedBox(
                height: 180,
                child: HoldControl(
                  enabled: true,
                  onChanged: events.add,
                  onTap: () {},
                  label: 'Approve',
                  icon: Icons.check,
                ),
              ),
              const SizedBox(height: 1500),
            ],
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldControl)),
    );
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(0, -100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(events, isEmpty);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('Canceling a recognized hold releases exactly once', (
    tester,
  ) async {
    final events = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              SizedBox(
                height: 180,
                child: HoldControl(
                  enabled: true,
                  onChanged: events.add,
                  onTap: () {},
                  label: 'Mic',
                  icon: Icons.mic,
                ),
              ),
              const SizedBox(height: 1500),
            ],
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldControl)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(events, [true]);
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    await gesture.up();
    expect(events, [true, false]);
  });

  testWidgets('Keyboard owns its held key across another key and pointer', (
    tester,
  ) async {
    final events = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: HoldControl(
          enabled: true,
          onChanged: events.add,
          onTap: () {},
          label: 'Mic',
          icon: Icons.mic,
        ),
      ),
    );
    final child = tester.element(
      find
          .descendant(
            of: find.byType(HoldControl),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    Focus.of(child).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    expect(events, [true]);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldControl)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.up();
    expect(events, [true]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(events, [true, false]);
  });

  testWidgets('Disabling a held control releases it', (tester) async {
    final events = <bool>[];
    Widget control(bool enabled) => MaterialApp(
      home: HoldControl(
        enabled: enabled,
        onChanged: events.add,
        onTap: () {},
        label: 'Mic',
        icon: Icons.mic,
      ),
    );
    await tester.pumpWidget(control(true));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldControl)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpWidget(control(false));
    expect(events, [true, false]);
    await gesture.up();
    expect(events, [true, false]);
  });
}

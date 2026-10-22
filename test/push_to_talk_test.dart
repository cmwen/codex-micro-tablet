import 'package:codex_micro_tablet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget screen(
    List<bool> events,
    ScrollController scroll, {
    bool enabled = true,
  }) => MaterialApp(
    home: Scaffold(
      body: ListView(
        controller: scroll,
        children: [
          SizedBox(
            height: 180,
            child: HoldControl(
              key: const ValueKey('ptt'),
              enabled: enabled,
              immediateHold: true,
              onChanged: events.add,
              onTap: () {},
              label: 'Hold to talk',
              subtitle: 'Mac microphone',
              icon: Icons.mic,
            ),
          ),
          const SizedBox(height: 1800),
        ],
      ),
    ),
  );

  testWidgets(
    'push to talk starts immediately and survives a scroll-sized drag',
    (tester) async {
      final events = <bool>[];
      final scroll = ScrollController();
      await tester.pumpWidget(screen(events, scroll));
      final press = await tester.startGesture(
        tester.getCenter(find.byType(HoldControl)),
      );
      expect(events, [true]);
      await tester.pump(const Duration(milliseconds: 150));
      await press.moveBy(const Offset(0, -100));
      await tester.pump(const Duration(seconds: 2));
      expect(events, [
        true,
      ], reason: 'Movement must not send a premature release');
      expect(scroll.offset, 0);
      expect(find.text('Hold active'), findsOneWidget);
      await press.up();
      expect(events, [true, false]);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );

  testWidgets(
    'push to talk ignores secondary pointer release and cancels once',
    (tester) async {
      final events = <bool>[];
      final scroll = ScrollController();
      await tester.pumpWidget(screen(events, scroll));
      final point = tester.getCenter(find.byType(HoldControl));
      final first = await tester.startGesture(point, pointer: 1);
      final second = await tester.startGesture(point, pointer: 2);
      await second.up();
      expect(events, [true]);
      await first.cancel();
      expect(events, [true, false]);
      await tester.pumpWidget(const SizedBox());
      expect(events, [true, false]);
      scroll.dispose();
    },
  );

  testWidgets('dashboard rebuilds do not interrupt a held microphone', (
    tester,
  ) async {
    final events = <bool>[];
    final scroll = ScrollController();
    await tester.pumpWidget(screen(events, scroll));
    final press = await tester.startGesture(
      tester.getCenter(find.byType(HoldControl)),
    );
    for (var refresh = 0; refresh < 4; refresh++) {
      await tester.pumpWidget(screen(events, scroll));
      await tester.pump(const Duration(seconds: 5));
      expect(events, [true]);
    }
    await press.up();
    expect(events, [true, false]);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });

  testWidgets('lost readiness releases a held microphone exactly once', (
    tester,
  ) async {
    final events = <bool>[];
    final scroll = ScrollController();
    await tester.pumpWidget(screen(events, scroll));
    final press = await tester.startGesture(
      tester.getCenter(find.byType(HoldControl)),
    );
    await tester.pumpWidget(screen(events, scroll, enabled: false));
    expect(events, [true, false]);
    await press.up();
    await tester.pumpWidget(const SizedBox());
    expect(events, [true, false]);
    scroll.dispose();
  });

  testWidgets('disabled microphone never sends a press', (tester) async {
    final events = <bool>[];
    final scroll = ScrollController();
    await tester.pumpWidget(screen(events, scroll, enabled: false));
    await tester.tap(find.byType(HoldControl));
    expect(events, isEmpty);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });
}

import 'package:codex_micro_tablet/usage_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 22, 12);
  Map<String, Object?> bucket(int used, DateTime reset) => {
    'used_percent': used,
    'resets_at': reset.millisecondsSinceEpoch ~/ 1000,
  };
  Widget panel({Map? usage, DateTime Function()? clock}) => MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: UsagePanel(
          usage: usage,
          status: 'Connected',
          onSettings: () {},
          onRefresh: () {},
          now: clock ?? () => now,
        ),
      ),
    ),
  );

  testWidgets('usage shows both windows and exact local resets', (
    tester,
  ) async {
    await tester.pumpWidget(
      panel(
        usage: {
          'five_hour': bucket(
            29,
            now.add(const Duration(hours: 2, minutes: 10)),
          ),
          'weekly': bucket(73, now.add(const Duration(days: 4, hours: 3))),
        },
      ),
    );
    expect(find.text('29% used'), findsOneWidget);
    expect(find.text('71% remaining'), findsOneWidget);
    expect(find.text('73% used'), findsOneWidget);
    expect(find.text('Resets in 2h 10m'), findsOneWidget);
    expect(find.text('Resets in 4d 3h'), findsOneWidget);
    expect(find.textContaining('October 22, 2026'), findsOneWidget);
    expect(find.textContaining('October 26, 2026'), findsOneWidget);
    expect(find.textContaining(now.timeZoneName), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('zero usage is distinct from unavailable usage', (tester) async {
    await tester.pumpWidget(
      panel(
        usage: {
          'five_hour': {'used_percent': 0},
          'weekly': {'used_percent': null},
        },
      ),
    );
    expect(find.text('0% used'), findsOneWidget);
    expect(find.text('100% remaining'), findsOneWidget);
    expect(find.text('Usage unavailable'), findsOneWidget);
    expect(find.text('Reset time unavailable'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('elapsed reset does not invent fresh allowance', (tester) async {
    await tester.pumpWidget(
      panel(
        usage: {
          'five_hour': bucket(100, now.subtract(const Duration(minutes: 1))),
        },
      ),
    );
    expect(find.text('100% used'), findsOneWidget);
    expect(find.text('Awaiting bridge reset update'), findsOneWidget);
    expect(find.text('0% used'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('countdown advances without a bridge update', (tester) async {
    var clock = now;
    await tester.pumpWidget(
      panel(
        clock: () => clock,
        usage: {'five_hour': bucket(42, now.add(const Duration(minutes: 2)))},
      ),
    );
    expect(find.text('Resets in 2m'), findsOneWidget);
    clock = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Resets in 1m'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lost snapshot clears percentages and reset dates', (
    tester,
  ) async {
    await tester.pumpWidget(
      panel(
        usage: {'five_hour': bucket(29, now.add(const Duration(hours: 1)))},
      ),
    );
    await tester.pumpWidget(panel());
    expect(find.text('29% used'), findsNothing);
    expect(find.text('Usage unavailable'), findsNWidgets(2));
    expect(find.textContaining('October 22, 2026'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [320.0, 533.0, 853.0]) {
    testWidgets('reset details fit width $width', (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        panel(
          usage: {
            'five_hour': bucket(99, now.add(const Duration(hours: 2))),
            'weekly': bucket(73, now.add(const Duration(days: 6))),
          },
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

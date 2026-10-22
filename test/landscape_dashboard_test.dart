import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_micro_tablet/main.dart';
import 'widget_test.dart' show FakeHid, FakeBridge;

void main() {
  for (final size in [
    const Size(853, 533),
    const Size(1280, 800),
    const Size(740, 400),
  ]) {
    testWidgets('landscape controls remain visible at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final hid = FakeHid()
        ..applyState({
          'connected': true,
          'discovered': true,
          'transportMode': 'usb',
        });
      final bridge = FakeBridge()
        ..updateSnapshot({
          'codex': {
            'usage': {
              'five_hour': {'used_percent': 26},
              'weekly': {'used_percent': 88},
            },
          },
          'agents': [
            {
              'id': 'thread-1',
              'name': 'Build dashboard',
              'status': 'running',
              'detail': 'Implementing landscape controls',
            },
            {
              'id': 'thread-2',
              'name': 'Review changes',
              'status': 'needs_attention',
              'detail': 'Waiting for your input',
            },
          ],
        });
      await tester.pumpWidget(MicroTabletApp(hid: hid, bridge: bridge));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('74%'), findsOneWidget);
      expect(find.text('12%'), findsOneWidget);
      expect(find.text('Mac microphone'), findsOneWidget);
      expect(find.text('Hold to talk').hitTestable(), findsOneWidget);
      expect(find.text('Send').hitTestable(), findsOneWidget);
      if (size.height >= 533) {
        expect(find.text('Down').hitTestable(), findsOneWidget);
      }
      await tester.ensureVisible(find.text('Build dashboard'));
      await tester.tap(find.text('Build dashboard'));
      await tester.pumpAndSettle();
      expect(find.text('Implementing landscape controls'), findsOneWidget);
      await tester.tap(find.text('Message'));
      await tester.pumpAndSettle();
      expect(find.text('Build dashboard'), findsWidgets);
      bridge.updateSnapshot({'codex': {}, 'agents': []});
      await tester.pumpAndSettle();
      expect(find.text('Selected chat unavailable'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Send through bridge'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      hid.dispose();
      bridge.dispose();
    });
  }

  testWidgets(
    'landscape holds release on disconnect and renders reference preview',
    (tester) async {
      tester.view.physicalSize = const Size(853, 533);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final hid = FakeHid()
        ..applyState({
          'connected': true,
          'discovered': true,
          'transportMode': 'usb',
          'hostName': 'Mac',
          'slots': [
            {'id': 0, 'present': true, 'color': 0x00cdeb},
            {'id': 1, 'present': true, 'color': 0xffc247},
          ],
        });
      final bridge = FakeBridge()
        ..updateSnapshot({
          'codex': {
            'usage': {
              'five_hour': {
                'used_percent': 26,
                'resets_at':
                    DateTime.now()
                        .add(const Duration(hours: 2))
                        .millisecondsSinceEpoch ~/
                    1000,
              },
              'weekly': {
                'used_percent': 88,
                'resets_at':
                    DateTime.now()
                        .add(const Duration(days: 3))
                        .millisecondsSinceEpoch ~/
                    1000,
              },
            },
          },
          'agents': [
            {
              'id': 'a',
              'name': 'Landscape dashboard',
              'status': 'running',
              'detail': 'Building the next release',
            },
            {
              'id': 'b',
              'name': 'Review USB controls',
              'status': 'needs_attention',
              'detail': 'Waiting for your review',
            },
            {'id': 'c', 'name': 'Documentation', 'status': 'idle'},
          ],
        });
      if (Platform.environment['CAPTURE_DASHBOARD'] == '1') {
        final fontDir = Platform.environment['DASHBOARD_FONT_DIR']!;
        for (final entry in {
          'Roboto': 'Roboto-Regular.ttf',
          'MaterialIcons': 'MaterialIcons-Regular.otf',
        }.entries) {
          final loader = FontLoader(entry.key)
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  File('$fontDir/${entry.value}').readAsBytesSync(),
                ),
              ),
            );
          await loader.load();
        }
      }
      bridge.baseUrl = 'http://monitor.local:8765';
      bridge.status = 'Bridge connected';
      const boundaryKey = ValueKey('preview');
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MicroTabletApp(hid: hid, bridge: bridge),
        ),
      );
      await tester.pumpAndSettle();
      if (Platform.environment['CAPTURE_DASHBOARD'] == '1') {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        await tester.runAsync(() async {
          final picture = await boundary.toImage(pixelRatio: 1.5);
          final data = await picture.toByteData(format: ui.ImageByteFormat.png);
          await Directory('docs/images').create(recursive: true);
          await File(
            'docs/images/landscape-dashboard.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          picture.dispose();
        });
      }
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('control-10'))),
      );
      await tester.pump();
      expect(hid.keys.last, (10, true));
      hid.applyState({
        'connected': false,
        'discovered': false,
        'transportMode': 'usb',
      });
      await tester.pump();
      expect(hid.keys.last, (10, false));
      await gesture.up();
      await tester.tap(find.byKey(const ValueKey('agent-0')));
      expect(hid.keys.where((key) => key.$1 == 0), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      hid.dispose();
      bridge.dispose();
    },
  );
}

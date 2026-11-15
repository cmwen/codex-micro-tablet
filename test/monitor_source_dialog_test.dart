import 'package:codex_micro_tablet/bridge_client.dart';
import 'package:codex_micro_tablet/monitor_source_dialog.dart';
import 'package:codex_micro_tablet/services/local_discovery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingBridge extends BridgeClient {
  RecordingBridge({this.failWith});
  final String? failWith;
  final origins = <String>[];
  final manual = <String>[];

  @override
  Future<void> configureReadOnly(String origin) async {
    origins.add(origin);
    if (failWith != null) throw FormatException(failWith!);
  }

  @override
  Future<void> configure(String url, String key) async {
    manual.add(url);
  }
}

Map<String, Object?> service({
  required String name,
  String host = '192.168.1.17',
  int port = 8082,
  Map<String, Object?>? attributes,
}) => {
  'name': name,
  'type': '_http._tcp.',
  'host': host,
  'port': port,
  'attributes':
      attributes ??
      {
        'path': '/',
        'protocol': 'http',
        'https': 'https://agent-deck-lan.home.cmwen.dev:8444',
      },
};

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalServiceDiscovery.channel, (call) async {
          if (call.method != 'discover') return null;
          return [
            service(name: 'Agent Deck'),
            service(
              name: 'LocalLink Speech Recognition',
              port: 8081,
              attributes: {'path': '/v1/audio/transcriptions'},
            ),
          ];
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalServiceDiscovery.channel, null);
  });

  Future<void> open(WidgetTester tester, BridgeClient bridge) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MonitorSourceDialog(bridge: bridge)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('discovery lists candidates and uses only an explicit choice', (
    tester,
  ) async {
    final bridge = RecordingBridge();
    addTearDown(bridge.dispose);
    await open(tester, bridge);

    expect(find.text('Monitor source'), findsOneWidget);
    expect(find.text('No monitor source is configured.'), findsOneWidget);
    await tester.tap(find.text('Find services'));
    await tester.pumpAndSettle();

    expect(find.text('Agent Deck'), findsOneWidget);
    expect(find.text('192.168.1.17:8081 · no HTTPS origin'), findsOneWidget);
    expect(
      find.text('Read-only · agent-deck-lan.home.cmwen.dev'),
      findsOneWidget,
    );
    expect(find.text('Not a monitor'), findsOneWidget);
    expect(bridge.origins, isEmpty);

    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();
    expect(bridge.origins, ['https://agent-deck-lan.home.cmwen.dev:8444']);
    expect(find.text('Monitor source'), findsNothing);
  });

  testWidgets('a rejected candidate is reported and never adopted', (
    tester,
  ) async {
    final bridge = RecordingBridge(
      failWith: 'Cannot reach that service over HTTPS.',
    );
    addTearDown(bridge.dispose);
    await open(tester, bridge);
    await tester.tap(find.text('Find services'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();
    expect(find.text('Cannot reach that service over HTTPS.'), findsOneWidget);
    expect(find.text('Monitor source'), findsOneWidget);
  });

  testWidgets('the manual bridge fallback stays available', (tester) async {
    final bridge = RecordingBridge();
    addTearDown(bridge.dispose);
    await open(tester, bridge);
    await tester.enterText(
      find.widgetWithText(TextField, 'Bridge address'),
      'http://192.168.1.17:8765',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Monitor key'),
      'local-key',
    );
    await tester.tap(find.text('Save & connect'));
    await tester.pumpAndSettle();
    expect(bridge.manual, ['http://192.168.1.17:8765']);
  });
}

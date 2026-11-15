import 'package:codex_micro_tablet/bridge_client.dart';
import 'package:codex_micro_tablet/hid_service.dart';
import 'package:codex_micro_tablet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OrientationHid extends HidService {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> refresh() async {}
  @override
  Future<void> releaseAll() async {}
  @override
  Future<bool> stop() async => true;
}

class OrientationBridge extends BridgeClient {
  @override
  Future<void> load() async {}
  @override
  Future<void> refresh() async {}
}

void main() {
  testWidgets(
    'saved standalone permits portrait; exit restores controller landscape',
    (tester) async {
      SharedPreferences.setMockInitialValues({'standalone_display': true});
      final requests = <List<String>>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          requests.add(List<String>.from(call.arguments as List));
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final hid = OrientationHid(), bridge = OrientationBridge();
      await tester.pumpWidget(MicroTabletApp(hid: hid, bridge: bridge));
      await tester.pumpAndSettle();
      expect(requests.last, contains('DeviceOrientation.portraitUp'));
      expect(requests.last, contains('DeviceOrientation.landscapeLeft'));
      await tester.tap(find.byTooltip('Exit standalone display'));
      await tester.pumpAndSettle();
      expect(requests.last, [
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
      await tester.tap(find.byTooltip('Standalone display'));
      await tester.pumpAndSettle();
      expect(requests.last, contains('DeviceOrientation.portraitUp'));
      await tester.pumpWidget(const SizedBox());
      hid.dispose();
      bridge.dispose();
    },
  );
}

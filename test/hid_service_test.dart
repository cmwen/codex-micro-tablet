import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_micro_tablet/hid_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('codex_micro/test_hid');
  final calls = <MethodCall>[];
  late HidService hid;
  setUp(() {
    calls.clear();
    hid = HidService(channel: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'status') {
            return {'supported': true, 'connected': true, 'discovered': false};
          }
          return true;
        });
  });
  tearDown(() {
    hid.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('OS connection is insufficient to send a control', () async {
    await hid.refresh();
    expect(hid.connected, isTrue);
    expect(hid.ready, isFalse);
    await hid.key(7, true);
    expect(calls.map((call) => call.method), ['status']);
    // Always permit a release even when the app loses discovery state.
    await hid.key(7, false);
    expect(calls.last.arguments, {'id': 7, 'pressed': false});
  });
  test('A Micro handshake enables balanced tap reports', () async {
    hid.applyState({'connected': true, 'discovered': true});
    expect(hid.ready, isTrue);
    await hid.tap(0);
    expect(calls.map((call) => call.arguments), [
      {'id': 0, 'pressed': true},
      {'id': 0, 'pressed': false},
    ]);
  });
  test('Native failures become visible diagnostics', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(
            code: 'permission_denied',
            message: 'Allow Bluetooth access',
          );
        });
    await hid.start();
    expect(hid.error, 'Allow Bluetooth access');
    expect(hid.ready, isFalse);
  });
}

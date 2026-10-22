import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Separates an OS Bluetooth link from a verified Micro protocol exchange.
class HidService extends ChangeNotifier {
  HidService({MethodChannel? channel, EventChannel? events})
    : _channel = channel ?? const MethodChannel('codex_micro/hid'),
      _events = events ?? const EventChannel('codex_micro/hid_events');

  final MethodChannel _channel;
  final EventChannel _events;
  StreamSubscription<dynamic>? _subscription;
  Map<String, dynamic> state = {};
  bool _disposed = false;

  bool get supported => state['supported'] == true;
  bool get registered => state['registered'] == true;
  bool get connected => state['connected'] == true;
  bool get discovered => state['discovered'] == true;
  String get transportMode => state['transportMode']?.toString() ?? 'ble';
  bool get isBle => transportMode == 'ble';
  bool get isUsb => transportMode == 'usb';
  bool get microphoneActive => state['microphoneActive'] == true;
  bool get advertising => state['advertising'] == true;
  bool get ready => connected && discovered;
  String get error => state['error']?.toString() ?? '';
  String get hostName => state['hostName']?.toString() ?? 'Mac';
  List<Map<String, dynamic>> get slots => (state['slots'] as List? ?? [])
      .whereType<Map>()
      .map((slot) => Map<String, dynamic>.from(slot))
      .toList();

  Future<void> initialize() async {
    _subscription = _events.receiveBroadcastStream().listen((event) {
      if (event is Map) applyState(Map<String, dynamic>.from(event));
    }, onError: (Object e) => _fail(e));
    await refresh();
  }

  @visibleForTesting
  void applyState(Map<String, dynamic> value) {
    if (_disposed) return;
    state = value;
    notifyListeners();
  }

  void _fail(Object error) {
    if (_disposed) return;
    state = {...state, 'error': error.toString()};
    notifyListeners();
  }

  Future<dynamic> invoke(String method, [Map<String, dynamic>? args]) async {
    try {
      final result = await _channel.invokeMethod<dynamic>(method, args);
      if (result is Map && result.containsKey('supported')) {
        applyState(Map<String, dynamic>.from(result));
      }
      return result;
    } on PlatformException catch (e) {
      _fail(e.message ?? e.code);
    } on MissingPluginException catch (e) {
      _fail(e);
    }
    return null;
  }

  Future<void> refresh() async => await invoke('status');
  Future<void> start() async => await invoke('start');
  Future<void> setTransport(bool ble) async =>
      await chooseTransport(ble ? 'ble' : 'classic');
  Future<void> chooseTransport(String transport) async =>
      await invoke('setTransport', {'transport': transport});
  Future<void> restoreUsb() async => await invoke('restoreUsb');
  Future<void> startMicrophone() async => await invoke('startMicrophone');
  Future<void> stopMicrophone() async => await invoke('stopMicrophone');
  Future<void> discoverable() async => await invoke('discoverable');
  Future<void> connect(String address) async =>
      await invoke('connect', {'address': address});
  Future<void> disconnect() async => await invoke('disconnect');
  Future<void> settings() async => await invoke('settings');
  Future<void> releaseAll() async => await invoke('releaseAll');

  Future<List<Map<String, dynamic>>> devices() async {
    final result = await invoke('devices');
    return (result as List? ?? [])
        .whereType<Map>()
        .map((device) => Map<String, dynamic>.from(device))
        .toList();
  }

  Future<void> key(int id, bool pressed) async {
    if (pressed && !ready) return;
    await invoke('key', {'id': id, 'pressed': pressed});
  }

  Future<void> tap(int id) async {
    if (!ready) return;
    await key(id, true);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await key(id, false);
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}

import 'package:codex_micro_tablet/services/local_discovery.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> service({
  String name = 'Agent Deck',
  String type = '_http._tcp.',
  String host = '192.168.1.17',
  Object? port = 8082,
  Map<String, Object?> attributes = const {
    'path': '/',
    'protocol': 'http',
    'https': 'https://agent-deck-lan.home.cmwen.dev:8444',
  },
}) => {
  'name': name,
  'type': type,
  'host': host,
  'port': port,
  'attributes': attributes,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = LocalServiceDiscovery.channel;
  List<Object?>? response;
  Object? failure;
  Map<Object?, Object?>? arguments;

  setUp(() {
    response = null;
    failure = null;
    arguments = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          arguments = call.arguments as Map<Object?, Object?>?;
          if (call.method == 'stop') return null;
          if (failure != null) throw failure!;
          return response;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'discovers and sorts verified candidates without choosing one',
    () async {
      response = [
        service(
          name: 'LocalLink Speech Recognition',
          host: '192.168.1.17',
          port: 8081,
          attributes: {'path': '/v1/audio/transcriptions', 'protocol': 'http'},
        ),
        service(),
        service(host: '192.168.1.17', port: 8082), // duplicate instance
        service(name: 'Bad port', port: 70000),
        // Android 10 OEM builds report the leading-dot form.
        service(name: 'OEM', type: '._http._tcp'),
        service(name: 'Bad type', type: '_http'),
        service(name: 'Bad host', host: 'agent deck'),
      ];
      final services = await const LocalServiceDiscovery().discover(
        timeout: const Duration(seconds: 4),
      );
      expect(arguments?['serviceType'], '_http._tcp.');
      expect(arguments?['timeoutMs'], 4000);
      expect(services.map((service) => service.name), [
        'Agent Deck',
        'LocalLink Speech Recognition',
      ]);
      final deck = services.first;
      expect(deck.advertisesAgentDeck, isTrue);
      expect(
        deck.httpsOrigin.toString(),
        'https://agent-deck-lan.home.cmwen.dev:8444',
      );
      expect(deck.describe(), 'Agent Deck · agent-deck-lan.home.cmwen.dev');
      expect(deck.unsupportedReason, isNull);
      expect(services.last.type, '_http._tcp.');
      final speech = services[1];
      expect(speech.advertisesAgentDeck, isFalse);
      expect(speech.httpsOrigin, isNull);
      expect(speech.unsupportedReason, 'No HTTPS monitor origin published');
      expect(speech.address, 'http://192.168.1.17:8081');
    },
  );

  test('clamps the browse window and reports platform failures', () async {
    response = [];
    await const LocalServiceDiscovery().discover(
      timeout: const Duration(milliseconds: 50),
    );
    expect(arguments?['timeoutMs'], 1500);

    failure = PlatformException(code: 'discovery_error', message: 'No LAN');
    await expectLater(
      const LocalServiceDiscovery().discover(),
      throwsA(
        isA<DiscoveryException>().having(
          (error) => error.message,
          'message',
          'No LAN',
        ),
      ),
    );
  });

  test('only plaintext-free monitor metadata becomes an origin', () {
    DiscoveredService parsed(Map<String, Object?> attributes) =>
        DiscoveredService.parse(service(attributes: attributes))!;

    for (final value in [
      'http://agent-deck.local:8082',
      'https://user:key@agent-deck.local:8444',
      'https://agent-deck.local:8444/?token=1',
      'https://agent-deck.local:8444/path',
      'https://agent-deck.local:8444/#fragment',
      'not a url',
    ]) {
      expect(parsed({'https': value}).httpsOrigin, isNull, reason: value);
    }
    expect(
      parsed({
        'https': 'https://agent-deck-lan.home.cmwen.dev:8444/',
      }).httpsOrigin,
      Uri.parse('https://agent-deck-lan.home.cmwen.dev:8444'),
    );
    // Unsafe TXT keys and non-printing values never reach the classifier.
    final filtered = parsed({
      'https': 'https://agent-deck-lan.home.cmwen.dev:8444',
      'monitor key': 'secret',
      'note': 'bell\u0007',
    });
    expect(filtered.attributes.keys, ['https']);
  });
}

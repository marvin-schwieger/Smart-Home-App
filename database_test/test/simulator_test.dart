import 'dart:convert';
import 'dart:io';

import 'package:database_test/auth/coap_security.dart';
import 'package:database_test/auth/device_auth.dart';
import 'package:database_test/auth/oscore.dart';
import 'package:database_test/database.dart';
import 'package:database_test/request.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Requests against device_simulator.py and http_simulator.py over the real
// network, with the test credentials from their docstrings. Skipped unless
// the address of the simulators is given, e.g.
//   flutter test test/simulator_test.dart --dart-define=SIMULATOR_HOST=172.30.13.2
// On https:// the CA from credentials/tls/ca.pem is used (make_test_certs.py)

const _host = String.fromEnvironment('SIMULATOR_HOST');
final _skip = _host.isEmpty ? 'SIMULATOR_HOST not set' : false;

// From test/ in database_test up to the credentials of the simulators
String _credential(String name) => File('../credentials/tls/$name').readAsStringSync();

const _oscore = DeviceAuth(AuthMethod.oscore, {
  'masterSecret': '0x0102030405060708090a0b0c0d0e0f10',
  'masterSalt': '0x9e7ca92223786340',
  'senderId': '',
  'recipientId': '0x01',
});

Future<Device> _device(
  String scheme,
  String path,
  DeviceAuth auth, {
  String method = 'GET',
  String payload = '',
  String? host,
}) async {
  final id = await database.into(database.devices).insert(
        DevicesCompanion.insert(
          roomId: 1,
          role: method == 'GET' ? DeviceRole.sensor : DeviceRole.actuator,
          name: path,
          host: host ?? _host,
          scheme: Value(scheme),
          path: Value(path),
          method: Value(method),
          payload: Value(payload),
          auth: Value(auth.encode()),
        ),
      );
  return (database.select(database.devices)..where((t) => t.id.equals(id))).getSingle();
}

Future<({String code, String body})> _fetch(Device device) =>
    fetchResponse(device, timeout: const Duration(seconds: 10));

// The contexts of device_simulator.py: the app's Sender ID picks the
// algorithm
const _algorithms = {
  '': ('AES-CCM-16-64-128', 'SHA-256'),
  '0x10': ('AES-CCM-16-128-128', 'SHA-256'),
  '0x11': ('A128GCM', 'SHA-256'),
  '0x12': ('A256GCM', 'SHA-256'),
  '0x13': ('ChaCha20/Poly1305', 'SHA-256'),
  '0x14': ('AES-CCM-16-64-128', 'SHA-384'),
  '0x15': ('AES-CCM-16-64-128', 'SHA-512'),
};

DeviceAuth _oscoreWith(String senderId) {
  final (algorithm, hkdf) = _algorithms[senderId]!;
  return _oscore
      .withValue('senderId', senderId)
      .withValue('algorithm', algorithm)
      .withValue('hkdf', hkdf);
}

// The simulator remembers the sequence numbers it has seen, and the
// database here is new for every run. So each run starts at a number no
// earlier run has reached
final _firstSequence = DateTime.now().millisecondsSinceEpoch ~/ 1000 * 64;

Future<void> _reserveSequence(int reserved, {DeviceAuth auth = _oscore}) async {
  forgetOscoreSequences();
  await database.into(database.oscoreSequences).insertOnConflictUpdate(
        OscoreSequencesCompanion.insert(
          context: oscoreContextId(OscoreContext.of(auth)),
          reserved: reserved,
        ),
      );
}

void main() {
  setUpAll(() async {
    database = AppDatabase(NativeDatabase.memory());
    for (final senderId in _algorithms.keys) {
      await _reserveSequence(_firstSequence, auth: _oscoreWith(senderId));
    }
  });
  tearDownAll(() => database.close());

  group('CoAP', () {
    for (final MapEntry(key: senderId, value: (algorithm, hkdf)) in _algorithms.entries) {
      test('OSCORE with $algorithm and HKDF $hkdf reads the protected sensor', () async {
        final device = await _device('coap', '/secure/temperature', _oscoreWith(senderId));

        final response = await _fetch(device);

        expect(response.code, '2.05 Content');
        expect(jsonDecode(response.body), containsPair('unit', '°C'));
      });
    }

    test('OSCORE switches the protected lamp', () async {
      final device = await _device(
        'coap',
        '/secure/lamp',
        _oscore,
        method: 'PUT',
        payload: '{"on":true,"brightness":42}',
      );

      final response = await _fetch(device);

      expect(response.code, '2.04 Changed');
      expect(jsonDecode(response.body), containsPair('brightness', 42));
    });

    test('a restarted app continues behind its reservation', () async {
      final device = await _device('coap', '/secure/temperature', _oscore);
      expect((await _fetch(device)).code, '2.05 Content');

      forgetOscoreSequences();

      expect((await _fetch(device)).code, '2.05 Content');
    });

    test('a reused sequence number is caught by the device', () async {
      final device = await _device('coap', '/secure/temperature', _oscore);
      // As if the reservation got lost, e.g. with a reinstalled app
      await _reserveSequence(_firstSequence);

      await expectLater(_fetch(device), throwsA(predicate((e) => '$e'.contains('Replay detected'))));

      await _reserveSequence(_firstSequence + 1000);
    });

    test('without OSCORE the protected sensor answers 4.01', () async {
      final device = await _device('coap', '/secure/temperature', DeviceAuth.none);

      expect((await _fetch(device)).code, startsWith('4.01'));
    });

    test('a wrong master secret is rejected', () async {
      final device = await _device(
        'coap',
        '/secure/temperature',
        _oscore.withValue('masterSecret', 'wrong'),
      );

      expect(_fetch(device), throwsA(predicate((e) => '$e'.contains('OSCORE'))));
    });
  }, skip: _skip);

  group('HTTP', () {
    const basic = DeviceAuth(AuthMethod.basic, {'username': 'admin', 'password': 'secret'});
    const oauth = DeviceAuth(AuthMethod.oauth2, {
      'tokenUrl': '/oauth/token',
      'clientId': 'app',
      'clientSecret': 'app-secret',
      'scope': 'read',
    });

    Future<({String code, String body})> get(String path, DeviceAuth auth, {String scheme = 'http'}) async =>
        _fetch(await _device(scheme, path, auth, host: '$_host:${scheme == 'https' ? 8443 : 8080}'));

    test('each method gets through its door, and only through its own', () async {
      for (final MapEntry(key: prefix, value: auth) in {'/basic': basic, '/oauth': oauth}.entries) {
        final allowed = await get('$prefix/temperature', auth);
        expect(allowed.code, '200', reason: prefix);
        expect(jsonDecode(allowed.body), containsPair('unit', '°C'), reason: prefix);
        expect((await get('$prefix/temperature', DeviceAuth.none)).code, '401', reason: prefix);
      }
      expect((await get('/oauth/temperature', basic)).code, '401');
    });

    test('a wrong password or client secret is rejected', () async {
      expect((await get('/basic/temperature', basic.withValue('password', 'wrong'))).code, '401');
      expect(
        get('/oauth/temperature', oauth.withValue('clientSecret', 'wrong')),
        throwsA(isA<AuthException>().having((e) => e.message, 'message', contains('invalid_client'))),
      );
    });

    test('https with the CA of the simulator', () async {
      final auth = basic.withValue('caCert', _credential('ca.pem'));
      expect((await get('/basic/temperature', auth, scheme: 'https')).code, '200');
    });

    test('https without the CA fails', () async {
      final response = get('/temperature', DeviceAuth.none, scheme: 'https');
      expect(response, throwsA(isA<HandshakeException>()));
    });
  }, skip: _skip);
}

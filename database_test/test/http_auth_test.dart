import 'dart:convert';

import 'package:database_test/auth/device_auth.dart';
import 'package:database_test/auth/http_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _uri = Uri.parse('http://device.local/temperature');

void main() {
  test('Basic sends username and password in the header', () async {
    late http.BaseRequest seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response('ok', 200);
    });
    const auth = DeviceAuth(AuthMethod.basic, {'username': 'Aladdin', 'password': 'open sesame'});

    await sendHttpRequest('GET', _uri, '', auth, client: client);

    // Example of RFC 7617 2
    expect(seen.headers['Authorization'], 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==');
  });

  test('OAuth fetches a token once and a new one when it is rejected', () async {
    var issued = 0;
    var valid = '';
    final tokenRequests = <http.Request>[];
    final client = MockClient((request) async {
      if (request.url.path == '/oauth/token') {
        tokenRequests.add(request);
        valid = 'token${++issued}';
        return http.Response(
          jsonEncode({'access_token': valid, 'token_type': 'Bearer', 'expires_in': 300}),
          200,
        );
      }
      return request.headers['Authorization'] == 'Bearer $valid'
          ? http.Response('ok', 200)
          : http.Response('', 401);
    });
    const auth = DeviceAuth(AuthMethod.oauth2, {
      'tokenUrl': '/oauth/token',
      'clientId': 'app',
      'clientSecret': 's3cret',
      'scope': 'read',
    });

    expect((await sendHttpRequest('GET', _uri, '', auth, client: client)).statusCode, 200);
    expect((await sendHttpRequest('GET', _uri, '', auth, client: client)).statusCode, 200);
    expect(issued, 1);

    // The device forgets its tokens, e.g. after a restart
    valid = 'nothing';
    expect((await sendHttpRequest('GET', _uri, '', auth, client: client)).statusCode, 200);
    expect(issued, 2);

    final tokenRequest = tokenRequests.first;
    expect(tokenRequest.url.toString(), 'http://device.local/oauth/token');
    expect(tokenRequest.headers['Authorization'], 'Basic ${base64.encode(utf8.encode('app:s3cret'))}');
    expect(tokenRequest.bodyFields, {'grant_type': 'client_credentials', 'scope': 'read'});
  });

  test('a rejected client gets a readable error', () async {
    final client = MockClient(
      (request) async => http.Response(jsonEncode({'error': 'invalid_client'}), 401),
    );
    const auth = DeviceAuth(AuthMethod.oauth2, {
      'tokenUrl': 'http://auth.local/token',
      'clientId': 'app',
      'clientSecret': 'wrong',
    });

    expect(
      () => sendHttpRequest('GET', _uri, '', auth, client: client),
      throwsA(isA<AuthException>().having((e) => e.message, 'message', contains('invalid_client'))),
    );
  });

  group('settings', () {
    test('are checked before saving', () {
      expect(DeviceAuth.none.validate('coap'), isNull);
      expect(DeviceAuth.none.validate('coaps'), isNotNull);
      expect(const DeviceAuth(AuthMethod.basic, {'username': 'a'}).validate('http'), 'Fill in password');
      expect(
        const DeviceAuth(AuthMethod.basic, {'username': 'a', 'password': 'b', 'caCert': 'x'}).validate('https'),
        contains('PEM'),
      );
      expect(const DeviceAuth(AuthMethod.oscore, {'masterSecret': '0x123'}).validate('coap'), contains('hex'));
      expect(
        const DeviceAuth(AuthMethod.oscore, {'masterSecret': 'secret', 'senderId': '0x01', 'recipientId': '0x01'})
            .validate('coap'),
        'Sender and recipient ID must differ',
      );
      expect(
        const DeviceAuth(AuthMethod.oscore, {'masterSecret': 'secret', 'recipientId': '0x0102030405060708'})
            .validate('coap'),
        contains('at most 7 bytes'),
      );
      expect(
        const DeviceAuth(AuthMethod.oscore, {'masterSecret': 'secret', 'recipientId': '0x01'}).validate('coap'),
        isNull,
      );
    });

    test('switching the scheme picks a method that fits', () {
      const basic = DeviceAuth(AuthMethod.basic, {'username': 'a', 'password': 'b'});

      expect(basic.forScheme('https').method, AuthMethod.basic);
      expect(basic.forScheme('coaps').method, AuthMethod.dtlsPsk);
      expect(basic.forScheme('coap').method, AuthMethod.none);
    });

    test('only the fields of the method are stored', () {
      final auth = DeviceAuth.none
          .withMethod(AuthMethod.oauth2)
          .withValue('clientId', 'app')
          .withMethod(AuthMethod.basic)
          .withValue('username', 'a')
          .withValue('password', 'b')
          .withValue('caCert', '-----BEGIN CERTIFICATE-----');

      final stored = DeviceAuth.decode(auth.cleanedFor('https').encode());

      expect(stored.method, AuthMethod.basic);
      expect(stored.values, {'username': 'a', 'password': 'b', 'caCert': '-----BEGIN CERTIFICATE-----'});
      expect(auth.cleanedFor('http').values.containsKey('caCert'), isFalse);
    });

    test('methods that no longer exist are read as none', () {
      expect(DeviceAuth.decode('{"method":"digest","username":"a"}').method, AuthMethod.none);
      expect(DeviceAuth.decode('not json'), same(DeviceAuth.none));
    });

    test('bytes are text or hex', () {
      expect(parseBytes('0x0aFF'), [10, 255]);
      expect(parseBytes('0x0a:ff'), [10, 255]);
      expect(parseBytes('ab'), [97, 98]);
      expect(tryParseBytes('0xabc'), isNull);
    });
  });
}

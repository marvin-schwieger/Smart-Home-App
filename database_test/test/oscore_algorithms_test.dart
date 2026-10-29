import 'dart:typed_data';

import 'package:database_test/auth/device_auth.dart';
import 'package:database_test/auth/oscore.dart';
import 'package:database_test/auth/oscore_algorithms.dart';
import 'package:flutter_test/flutter_test.dart';

// Every algorithm the app offers against vectors made with aiocoap: the app
// protects GET /secure/temperature with sequence number 0, the device answers
// 2.05 "21.5". Master Secret and Salt as in RFC 8613 C.1.1, app Sender ID
// empty, Recipient ID 0x01

Uint8List _hex(String hex) => Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

String _toHex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

typedef _Vector = ({
  String senderKey,
  String recipientKey,
  String commonIv,
  String requestCiphertext,
  String responseCiphertext,
});

const Map<(String, String), _Vector> _vectors = {
  ('AES-CCM-16-64-128', 'SHA-256'): (
    senderKey: 'f0910ed7295e6ad4b54fc793154302ff',
    recipientKey: 'ffb14e093c94c9cac9471648b4f98710',
    commonIv: '4622d4dd6d944168eefb54987c',
    requestCiphertext: 'ae8f2d1072995ff3b5f2b311b284202245204df329bae9852a8cfd60',
    responseCiphertext: '18c28e028768706e4d41b6c2f8f9',
  ),
  ('AES-CCM-16-128-128', 'SHA-256'): (
    senderKey: '996959531b57e9723ca9c27b54ab201f',
    recipientKey: '5ec80968acecc5fb714e57834c2e1f5e',
    commonIv: 'bbc0ff1df379d836ecb104bfe8',
    requestCiphertext: 'b6d0a4ab069b6a0d9131e8c1bf198d50e79e88b47faace29f740a1fe74d768dfe1f238d1',
    responseCiphertext: '33d8368a90f09efd87d836ecd9e2eb507a2a2e675b45',
  ),
  ('A128GCM', 'SHA-256'): (
    senderKey: '70c4c8cb554a796768f3e69932685cdf',
    recipientKey: 'a57918b1b1e153325c2696f9fe26fa14',
    commonIv: '18e102041155706c199c561a',
    requestCiphertext: '74db2b7d90cf06c5646288c8fb4c4c76a9a66a14834f20d55268950a369b23ac8230ea15',
    responseCiphertext: '16928a60d0dde39e657e8662bb1739192724f5d55e1f',
  ),
  ('A256GCM', 'SHA-256'): (
    senderKey: '5a828cdc2d3bfe699b2ee6a9070cedf97ad2835523c17e2cd808ef8425b319ce',
    recipientKey: 'bd8d3ce647d24408ed8a4e9d14c629bf40738ec69786d2b87c34a8454a7983c2',
    commonIv: '15ac68bccb2d1b049219393b',
    requestCiphertext: 'a54bdbb2e1d386268a8aee8ee94b763e7b43c6dab9086aceb82077d3d71e7d067fa01bec',
    responseCiphertext: 'a7e039fd401d6ae0c4ab935eba1c37cbb0d1593f822d',
  ),
  ('ChaCha20/Poly1305', 'SHA-256'): (
    senderKey: 'd5301eb18d067849950893ba2ac891417c89ae09df4a3855aa000ac9fff38751',
    recipientKey: '32882a1c6190308438ec98e6a932f020708f3739dfe46d77989b039b1ffc1cac',
    commonIv: '64f0bd314d4be03c270c2b1c',
    requestCiphertext: '5c94dd3f80e79368412b1eb3e92fd139a9db3c1fff0b393eb09df8609714e2085510e142',
    responseCiphertext: 'b88e7189e9d8739c1eeaf58f6ebf7fb820957f6bf76f',
  ),
  ('AES-CCM-16-64-128', 'SHA-384'): (
    senderKey: '1c0a70c633c947dc9c08ef509493b687',
    recipientKey: '6c5a6ba1cf2f7897255fc5bca7391e45',
    commonIv: 'c58d2cecb91188ca6e6c296896',
    requestCiphertext: 'e2d318b9e7904cb1a6a4df87f669cd47388d8c0a25af1385c3b4cb58',
    responseCiphertext: '8e72e43bb0369cf8ff8ef77b9d8c',
  ),
  ('AES-CCM-16-64-128', 'SHA-512'): (
    senderKey: 'cb7f4a1ecf9423bb470262ec670302dc',
    recipientKey: 'bbaf9de7b437dd1800d923bb1c0262a7',
    commonIv: '61bb6f7145bee3eee8cec81d12',
    requestCiphertext: 'f3fb8c7299dc852d22e8f811666283f55e6f918692f1ecfaad419e53',
    responseCiphertext: 'ee6ccf81addf5a368bf1145b9c11',
  ),
};

void main() {
  test('every offered algorithm has a vector', () {
    final offered = {
      for (final algorithm in OscoreAlgorithm.labels) (algorithm, 'SHA-256'),
      for (final hkdf in OscoreHkdf.labels) ('AES-CCM-16-64-128', hkdf),
    };
    expect(_vectors.keys.toSet(), offered);
  });

  for (final MapEntry(key: (algorithm, hkdf), value: vector) in _vectors.entries) {
    test('$algorithm with HKDF $hkdf matches aiocoap', () {
      final context = OscoreContext.of(DeviceAuth(AuthMethod.oscore, {
        'masterSecret': '0x0102030405060708090a0b0c0d0e0f10',
        'masterSalt': '0x9e7ca92223786340',
        'recipientId': '0x01',
        'algorithm': algorithm,
        'hkdf': hkdf,
      }));
      expect(_toHex(context.senderKey), vector.senderKey);
      expect(_toHex(context.recipientKey), vector.recipientKey);
      expect(_toHex(context.commonIv), vector.commonIv);

      final request = OscoreRequest.of('GET', Uri.parse('coap://h/secure/temperature'), const []);
      final protected = protectRequest(context, request, 0);
      expect(_toHex(protected.option), '0900');
      expect(_toHex(protected.ciphertext), vector.requestCiphertext);

      final response = unprotectResponse(context, protected, const [], _hex(vector.responseCiphertext));
      expect(response.codeText, '2.05 Content');
      expect(String.fromCharCodes(response.payload), '21.5');
    });
  }

  test('a response protected with another algorithm is rejected', () {
    DeviceAuth auth(String algorithm) => DeviceAuth(AuthMethod.oscore, {
          'masterSecret': '0x0102030405060708090a0b0c0d0e0f10',
          'masterSalt': '0x9e7ca92223786340',
          'recipientId': '0x01',
          'algorithm': algorithm,
        });
    final context = OscoreContext.of(auth('A128GCM'));
    final request = OscoreRequest.of('GET', Uri.parse('coap://h/secure/temperature'), const []);
    final protected = protectRequest(context, request, 0);

    expect(
      () => unprotectResponse(context, protected, const [], _hex(_vectors[('A256GCM', 'SHA-256')]!.responseCiphertext)),
      throwsA(isA<OscoreException>()),
    );
  });

  test('IDs may be one byte shorter with the 12 byte nonce of GCM and ChaCha20', () {
    DeviceAuth auth(String algorithm) => DeviceAuth(AuthMethod.oscore, {
          'masterSecret': 'secret',
          'recipientId': '0x01020304050607',
          'algorithm': algorithm,
        });

    expect(auth('AES-CCM-16-64-128').validate('coap'), isNull);
    expect(auth('A128GCM').validate('coap'), contains('at most 6 bytes'));
    expect(auth('ChaCha20/Poly1305').validate('coap'), contains('at most 6 bytes'));
    expect(auth('AES-CCM-8-8-8').validate('coap'), contains('not supported'));
  });
}

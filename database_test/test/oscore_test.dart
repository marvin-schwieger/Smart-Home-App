import 'dart:typed_data';

import 'package:database_test/auth/oscore.dart';
import 'package:flutter_test/flutter_test.dart';

// Test vectors from RFC 8613 Appendix C: the client of C.1.1 sends the
// request of C.4 and gets the response of C.7

Uint8List _hex(String hex) => Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

String _toHex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

final _client = OscoreContext.derive(
  masterSecret: _hex('0102030405060708090a0b0c0d0e0f10'),
  masterSalt: _hex('9e7ca92223786340'),
  senderId: const [],
  recipientId: _hex('01'),
);

// GET coap://localhost/tv1, without the Uri-Host that stays outside
final _request = OscoreRequest(0x01, [CoapOption(11, 'tv1'.codeUnits)], const []);

void main() {
  test('keys are derived like in C.1.1', () {
    expect(_toHex(_client.senderKey), 'f0910ed7295e6ad4b54fc793154302ff');
    expect(_toHex(_client.recipientKey), 'ffb14e093c94c9cac9471648b4f98710');
    expect(_toHex(_client.commonIv), '4622d4dd6d944168eefb54987c');
  });

  test('the request is protected like in C.4', () {
    final protected = protectRequest(_client, _request, 20);

    expect(_toHex(protected.option), '0914');
    expect(_toHex(protected.nonce), '4622d4dd6d944168eefb549868');
    expect(_toHex(protected.ciphertext), '612f1092f1776f1c1668b3825e');
  });

  test('the protected request is a valid outer CoAP message', () {
    final protected = protectRequest(_client, _request, 20);
    final message = CoapMessage(
      type: CoapMessage.confirmable,
      code: 0x02,
      messageId: 0x5d1f,
      token: _hex('00003974'),
      options: [CoapOption(3, 'localhost'.codeUnits), CoapOption(9, protected.option)],
      payload: protected.ciphertext,
    );

    expect(
      _toHex(message.encode()),
      '44025d1f00003974396c6f63616c686f7374620914ff612f1092f1776f1c1668b3825e',
    );
  });

  test('the response of C.7 is verified and decrypted', () {
    final protected = protectRequest(_client, _request, 20);
    final reply = CoapMessage.tryDecode(
      _hex('64445d1f0000397490ffdbaad1e9a7e7b2a813d3c31524378303cdafae119106'),
    )!;

    final response = unprotectResponse(_client, protected, reply.option(9)!, reply.payload);

    expect(response.codeText, '2.05 Content');
    expect(String.fromCharCodes(response.payload), 'Hello World!');
  });

  test('a manipulated response is rejected', () {
    final protected = protectRequest(_client, _request, 20);
    final ciphertext = _hex('dbaad1e9a7e7b2a813d3c31524378303cdafae119107');

    expect(
      () => unprotectResponse(_client, protected, const [], ciphertext),
      throwsA(isA<OscoreException>()),
    );
  });

  test('options with long values and large numbers survive a round trip', () {
    final options = [
      CoapOption(11, List.filled(300, 0x61)),
      CoapOption(252, _hex('0102')),
      const CoapOption(12, []),
    ];
    final encoded = [...encodeCoapOptions(options), 0xFF, 0x42];

    final (decoded, payloadStart) = decodeCoapOptions(encoded, 0);

    expect(decoded.map((o) => o.number), [11, 12, 252]);
    expect(decoded.first.value.length, 300);
    expect(encoded.sublist(payloadStart), [0x42]);
  });

  test('a request carries method, path, query and payload inside', () {
    final request = OscoreRequest.of(
      'PUT',
      Uri.parse('coap://host/secure/lamp?mode=fast'),
      '{"on":true}'.codeUnits,
    );

    expect(request.code, 0x03);
    expect(
      request.options.map((o) => (o.number, String.fromCharCodes(o.value))),
      [(11, 'secure'), (11, 'lamp'), (12, ''), (15, 'mode=fast')],
    );
  });
}

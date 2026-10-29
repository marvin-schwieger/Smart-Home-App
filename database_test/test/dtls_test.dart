import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:database_test/auth/device_auth.dart';
import 'package:database_test/auth/oscore.dart' show CoapMessage;
import 'package:database_test/database.dart';
import 'package:database_test/request.dart';
import 'package:dtls2/dtls2.dart';
import 'package:flutter_test/flutter_test.dart';

// coaps:// with a pre-shared key, against a small DTLS server of dtls2 that
// answers every CoAP request with 2.05 "21.5". device_simulator.py can do
// the same, but needs DTLSSocket. Both sides need OpenSSL 3, on Windows e.g.
// the one of Git for Windows in the PATH; skipped without it

bool _hasOpenSsl() {
  try {
    DynamicLibrary.open(switch (Platform.operatingSystem) {
      'windows' => 'libssl-3-x64.dll',
      'macos' => 'libssl.3.dylib',
      _ => 'libssl.so.3',
    });
    return true;
  } on ArgumentError {
    return false;
  }
}

Device _device(int port, String psk) => Device(
      id: 1,
      roomId: 1,
      role: DeviceRole.sensor,
      name: 'Thermo',
      scheme: 'coaps',
      host: '127.0.0.1:$port',
      path: '/secure/temperature',
      method: 'GET',
      payload: '',
      auth: DeviceAuth(AuthMethod.dtlsPsk, {'identity': 'app', 'psk': psk}).encode(),
    );

void main() {
  late DtlsServer server;
  late int port;

  setUpAll(() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = socket.port;
    server = DtlsServer(
      socket,
      DtlsServerContext(
        pskKeyStoreCallback: (identity) =>
            utf8.decode(identity) == 'app' ? utf8.encode('secretPSK') : null,
        ciphers: 'PSK-AES128-CCM8',
        securityLevel: 0,
      ),
    );
    server.listen((connection) {
      connection.listen((datagram) {
        final request = CoapMessage.tryDecode(datagram.data);
        if (request == null) return;
        connection.send(
          CoapMessage(
            type: CoapMessage.acknowledgement,
            code: 0x45,
            messageId: request.messageId,
            token: request.token,
            payload: utf8.encode('21.5'),
          ).encode(),
        );
      });
    });
  });
  tearDownAll(() => server.close());

  final skip = _hasOpenSsl() ? false : 'OpenSSL 3 not found';

  test('the right key gets an answer', () async {
    final response = await fetchResponse(_device(port, 'secretPSK'), timeout: const Duration(seconds: 15));

    expect((response.code, response.body), ('2.05 Content', '21.5'));
  }, skip: skip);

  test('a wrong key fails the handshake', () async {
    await expectLater(
      fetchResponse(_device(port, '0x00112233'), timeout: const Duration(seconds: 15)),
      throwsA(anything),
    );
  }, skip: skip);
}

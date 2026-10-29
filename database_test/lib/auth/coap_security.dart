import 'dart:convert';
import 'dart:io';

import 'package:coap/coap.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../database.dart';
import 'device_auth.dart';
import 'oscore.dart';

// DTLS

// coaps:// is handled by the coap package with OpenSSL (package dtls2). The
// libraries libssl and libcrypto have to be installed on Windows and bundled
// with the app on Android and iOS, see the README of dtls2
class _DtlsPskConfig extends CoapConfigAll {
  // With a pre-shared key there are no certificates to check
  @override
  bool get dtlsVerify => false;

  @override
  bool get dtlsWithTrustedRoots => false;

  // Few cipher suites on purpose: with too many the ClientHello gets
  // fragmented and the handshake fails (see the README of dtls2). CCM_8 is
  // the one RFC 7252 requires and the only one tinydtls (aiocoap) speaks
  @override
  String get dtlsCiphers => 'PSK-AES128-CCM8:PSK-AES128-CCM:PSK-AES128-GCM-SHA256';

  // OpenSSL counts CCM_8 as weak and refuses it on higher levels
  @override
  int get openSslSecurityLevel => 0;
}

// Client for coap://, and for coaps:// with the pre-shared key of the device
CoapClient coapClient(Uri uri, DeviceAuth auth) => auth.method == AuthMethod.dtlsPsk
    ? CoapClient(
        uri,
        config: _DtlsPskConfig(),
        pskCredentialsCallback: (_) => PskCredentials(
          identity: utf8.encode(auth['identity']),
          preSharedKey: auth.bytes('psk'),
        ),
      )
    : CoapClient(uri, config: CoapConfigAll());

// OSCORE

// Sends a request protected with OSCORE, see oscore.dart
Future<({String code, String body})> fetchOscore(
  String method,
  Uri uri,
  DeviceAuth auth,
  String payload, {
  Duration? timeout,
}) async {
  final addresses = await InternetAddress.lookup(uri.host);
  final context = OscoreContext.of(auth);
  final response = await sendOscoreRequest(
    address: addresses.first,
    port: uri.port,
    context: context,
    request: OscoreRequest.of(method, uri, utf8.encode(payload)),
    nextSequence: () => takeOscoreSequence(context),
    timeout: timeout,
  );
  return (code: response.codeText, body: utf8.decode(response.payload, allowMalformed: true));
}

// A sequence number must never be sent twice with the same key, otherwise
// the nonce repeats and AES-CCM loses its protection. So the numbers are
// reserved in steps in the database before they are used, and after a
// restart the app continues behind the last reservation (RFC 8613 B.1.1).
// They are counted per security context, not per device: two devices of the
// app may talk to the same endpoint with the same keys
const int _sequenceStep = 32;

class _Sequence {
  int next;
  int reserved;
  Future<void>? saving;

  _Sequence(this.next, this.reserved);
}

// Loaded once per context and app session, by [oscoreContextId]
final Map<String, Future<_Sequence>> _sequences = {};

// Like an app restart: the next numbers continue behind the stored
// reservations
@visibleForTesting
void forgetOscoreSequences() => _sequences.clear();

// Same Sender Key, Common IV and Sender ID give the same nonces. Hashed, so
// the key itself isn't stored a second time
String oscoreContextId(OscoreContext context) =>
    sha256.convert([...context.senderKey, ...context.commonIv, ...context.senderId]).toString();

// Next sender sequence number of [context], unique for its whole lifetime
Future<int> takeOscoreSequence(OscoreContext context) async {
  final id = oscoreContextId(context);
  final loading = _sequences[id] ??= _loadSequence(id);
  try {
    final sequence = await loading;
    // Taken before the next await, so two requests never get the same one
    final number = sequence.next++;
    if (number >= sequence.reserved) {
      sequence.reserved = number + _sequenceStep;
      sequence.saving = _saveSequence(id, sequence.reserved);
    }
    // Used only once its reservation is stored
    await sequence.saving;
    return number;
  } catch (_) {
    // Loaded again next time, from the last reservation that was stored
    if (_sequences[id] == loading) _sequences.remove(id);
    rethrow;
  }
}

Future<_Sequence> _loadSequence(String id) async {
  final row = await (database.select(database.oscoreSequences)..where((t) => t.context.equals(id)))
      .getSingleOrNull();
  final reserved = row?.reserved ?? 0;
  return _Sequence(reserved, reserved);
}

Future<void> _saveSequence(String id, int reserved) => database
    .into(database.oscoreSequences)
    .insertOnConflictUpdate(OscoreSequencesCompanion.insert(context: id, reserved: reserved));

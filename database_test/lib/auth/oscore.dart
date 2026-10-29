import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:coap/coap.dart' show CoapCode;

import 'device_auth.dart';
import 'oscore_algorithms.dart';

// OSCORE (RFC 8613): every request is encrypted and authenticated end-to-end
// with keys both sides derived from the same Master Secret. The algorithms
// to choose from are in oscore_algorithms.dart.
//
// The coap package can't be used here, its decoder fails on the empty OSCORE
// option most responses carry. So the protected message is sent with the
// small CoAP over UDP exchange at the end of this file

// Partial IVs have at most 5 bytes
const int maxOscoreSequence = (1 << 40) - 1;

// CoAP option numbers used here
const int _optionOscore = 9;
const int _optionUriPath = 11;
const int _optionContentFormat = 12;
const int _optionUriQuery = 15;
const int _optionEcho = 252;

const int _codePost = 0x02;
const int _codeUnauthorized = 0x81; // 4.01

class OscoreException implements Exception {
  final String message;

  const OscoreException(this.message);

  @override
  String toString() => 'OSCORE: $message';
}

// Keys of one side derived from the shared settings (RFC 8613 3.2)
class OscoreContext {
  final OscoreAlgorithm algorithm;
  final Uint8List senderId;
  final Uint8List recipientId;
  final Uint8List? idContext;
  final Uint8List senderKey;
  final Uint8List recipientKey;
  final Uint8List commonIv;

  OscoreContext._(
    this.algorithm,
    this.senderId,
    this.recipientId,
    this.idContext,
    this.senderKey,
    this.recipientKey,
    this.commonIv,
  );

  factory OscoreContext.derive({
    required List<int> masterSecret,
    List<int> masterSalt = const [],
    required List<int> senderId,
    required List<int> recipientId,
    List<int>? idContext,
    OscoreAlgorithm algorithm = OscoreAlgorithm.aesCcm,
    OscoreHkdf hkdf = OscoreHkdf.sha256,
  }) {
    Uint8List derive(List<int> id, String type, int length) => hkdf.derive(
          masterSalt,
          masterSecret,
          _info(id, idContext, algorithm, type, length),
          length,
        );

    return OscoreContext._(
      algorithm,
      Uint8List.fromList(senderId),
      Uint8List.fromList(recipientId),
      idContext == null ? null : Uint8List.fromList(idContext),
      derive(senderId, 'Key', algorithm.keyLength),
      derive(recipientId, 'Key', algorithm.keyLength),
      derive(const [], 'IV', algorithm.nonceLength),
    );
  }

  // Settings of a device, see the OSCORE entry in device_auth.dart
  factory OscoreContext.of(DeviceAuth auth) {
    final idContext = auth.bytes('idContext');
    return OscoreContext.derive(
      masterSecret: auth.bytes('masterSecret'),
      masterSalt: auth.bytes('masterSalt'),
      senderId: auth.bytes('senderId'),
      recipientId: auth.bytes('recipientId'),
      idContext: idContext.isEmpty ? null : idContext,
      algorithm: OscoreAlgorithm.byLabel(auth['algorithm']),
      hkdf: OscoreHkdf.byLabel(auth['hkdf']),
    );
  }

  // RFC 8613 5.2: the ID of the side that chose the Partial IV and the
  // Partial IV, both padded, XORed with the Common IV
  Uint8List nonce(List<int> idPiv, List<int> partialIv) {
    final length = algorithm.nonceLength;
    final nonce = Uint8List(length);
    nonce[0] = idPiv.length;
    nonce.setRange(length - 5 - idPiv.length, length - 5, idPiv);
    nonce.setRange(length - partialIv.length, length, partialIv);
    for (var i = 0; i < length; i++) {
      nonce[i] ^= commonIv[i];
    }
    return nonce;
  }
}

// A request before protection: the real method, the options only the device
// may read and the payload
class OscoreRequest {
  final int code;
  final List<CoapOption> options;
  final List<int> payload;

  const OscoreRequest(this.code, this.options, this.payload);

  // [method] is GET, POST, PUT or DELETE
  factory OscoreRequest.of(String method, Uri uri, List<int> payload) => OscoreRequest(
        switch (method) {
          'POST' => 0x02,
          'PUT' => 0x03,
          'DELETE' => 0x04,
          _ => 0x01,
        },
        [
          for (final segment in uri.pathSegments)
            if (segment.isNotEmpty) CoapOption(_optionUriPath, utf8.encode(segment)),
          // Like the coap package, a payload is marked as text/plain
          if (payload.isNotEmpty) const CoapOption(_optionContentFormat, []),
          if (uri.hasQuery)
            for (final part in uri.query.split('&'))
              CoapOption(_optionUriQuery, utf8.encode(Uri.decodeQueryComponent(part))),
        ],
        payload,
      );

  OscoreRequest withEcho(List<int> echo) =>
      OscoreRequest(code, [...options, CoapOption(_optionEcho, echo)], payload);
}

// A request after protection: what goes into the outer CoAP message
class ProtectedRequest {
  // Value of the OSCORE option
  final Uint8List option;
  final Uint8List ciphertext;

  // Needed to verify the response
  final Uint8List partialIv;
  final Uint8List nonce;

  const ProtectedRequest(this.option, this.ciphertext, this.partialIv, this.nonce);
}

class OscoreResponse {
  final int code;
  final List<CoapOption> options;
  final Uint8List payload;

  const OscoreResponse(this.code, this.options, this.payload);

  // e.g. 2.05
  String get codeText => formatCoapCode(code);

  List<int>? option(int number) {
    for (final option in options) {
      if (option.number == number) return option.value;
    }
    return null;
  }
}

// RFC 8613 8.1: encrypts the request with the sequence number [sequence],
// which must never be used again with the same Sender Key
ProtectedRequest protectRequest(OscoreContext context, OscoreRequest request, int sequence) {
  if (sequence < 0 || sequence > maxOscoreSequence) {
    throw const OscoreException('Sequence numbers are used up, derive new keys');
  }
  final partialIv = _partialIv(sequence);
  final nonce = context.nonce(context.senderId, partialIv);
  final plaintext = [
    request.code,
    ...encodeCoapOptions(request.options),
    if (request.payload.isNotEmpty) ...[0xFF, ...request.payload],
  ];
  final ciphertext = context.algorithm.process(
    true,
    context.senderKey,
    nonce,
    _aad(context.algorithm, context.senderId, partialIv),
    Uint8List.fromList(plaintext),
  );

  final idContext = context.idContext;
  final option = Uint8List.fromList([
    // flags: kid context present, kid present, length of the Partial IV
    (idContext != null ? 0x10 : 0) | 0x08 | partialIv.length,
    ...partialIv,
    if (idContext != null) ...[idContext.length, ...idContext],
    ...context.senderId,
  ]);
  return ProtectedRequest(option, ciphertext, partialIv, nonce);
}

// RFC 8613 8.4: decrypts and verifies the response to [request]. [option] is
// the value of its OSCORE option, usually empty
OscoreResponse unprotectResponse(
  OscoreContext context,
  ProtectedRequest request,
  List<int> option,
  List<int> ciphertext,
) {
  var nonce = request.nonce;
  if (option.isNotEmpty) {
    final length = option[0] & 0x07;
    if (length > 5 || option.length < 1 + length) {
      throw const OscoreException('Invalid OSCORE option in the response');
    }
    // The device chose its own Partial IV instead of reusing the request nonce
    if (length > 0) nonce = context.nonce(context.recipientId, option.sublist(1, 1 + length));
  }

  final Uint8List plaintext;
  try {
    plaintext = context.algorithm.process(
      false,
      context.recipientKey,
      nonce,
      _aad(context.algorithm, context.senderId, request.partialIv),
      Uint8List.fromList(ciphertext),
    );
  } catch (_) {
    // A wrong tag, which pointycastle reports differently per algorithm, or
    // a ciphertext shorter than the tag
    throw const OscoreException('The response could not be verified - do the keys and the algorithm match?');
  }
  if (plaintext.isEmpty) throw const OscoreException('Empty plaintext');

  final (options, payloadStart) = decodeCoapOptions(plaintext, 1);
  return OscoreResponse(plaintext[0], options, plaintext.sublist(payloadStart));
}

// Sends [request] protected to [address]:[port] and returns the verified
// response. [nextSequence] hands out the sequence numbers, see
// coap_security.dart. A device that lost its replay window answers the first
// request with 4.01 and an Echo option (RFC 9175), which is sent back once
Future<OscoreResponse> sendOscoreRequest({
  required InternetAddress address,
  required int port,
  required OscoreContext context,
  required OscoreRequest request,
  required Future<int> Function() nextSequence,
  Duration? timeout,
}) async {
  final deadline = DateTime.now().add(timeout ?? _maxTransmitWait);
  var current = request;
  for (var attempt = 0;; attempt++) {
    final protected = protectRequest(context, current, await nextSequence());
    final reply = await coapExchange(
      address,
      port,
      CoapMessage(
        type: CoapMessage.confirmable,
        code: _codePost,
        messageId: _random.nextInt(0x10000),
        token: _randomBytes(8),
        options: [CoapOption(_optionOscore, protected.option)],
        payload: protected.ciphertext,
      ),
      timeout: deadline.difference(DateTime.now()),
    );

    final option = reply.option(_optionOscore);
    if (option == null) {
      // An error the device couldn't protect, e.g. no matching context
      final reason = utf8.decode(reply.payload, allowMalformed: true);
      throw OscoreException(
        'Device answered unprotected ${formatCoapCode(reply.code)}'
        '${reason.isEmpty ? '' : ': $reason'}',
      );
    }
    final response = unprotectResponse(context, protected, option, reply.payload);
    final echo = response.option(_optionEcho);
    if (response.code != _codeUnauthorized || echo == null || attempt > 0) return response;
    current = request.withEcho(echo);
  }
}

// e.g. 0x45 -> 2.05 Content, like the responses of the coap package
String formatCoapCode(int code) =>
    CoapCode.decode(code)?.toString() ?? '${code >> 5}.${(code & 0x1F).toString().padLeft(2, '0')}';

Uint8List _partialIv(int sequence) {
  final bytes = <int>[];
  for (var rest = sequence; rest > 0; rest >>= 8) {
    bytes.insert(0, rest & 0xFF);
  }
  // 0 is sent as one zero byte
  return Uint8List.fromList(bytes.isEmpty ? [0] : bytes);
}

// RFC 8613 3.2.1: info = [id, id_context, alg_aead, type, L]
List<int> _info(
  List<int> id,
  List<int>? idContext,
  OscoreAlgorithm algorithm,
  String type,
  int length,
) =>
    _cborArray([
      _cborBytes(id),
      if (idContext == null) _cborNull else _cborBytes(idContext),
      _cborUint(algorithm.coseId),
      _cborText(type),
      _cborUint(length),
    ]);

// RFC 8613 5.4: Enc_structure of COSE with the external_aad of the request.
// No Class I options are used, so that list stays empty
Uint8List _aad(OscoreAlgorithm algorithm, List<int> requestKid, List<int> requestPiv) {
  final externalAad = _cborArray([
    _cborUint(1),
    _cborArray([_cborUint(algorithm.coseId)]),
    _cborBytes(requestKid),
    _cborBytes(requestPiv),
    _cborBytes(const []),
  ]);
  return Uint8List.fromList(
    _cborArray([_cborText('Encrypt0'), _cborBytes(const []), _cborBytes(externalAad)]),
  );
}

// Just the CBOR (RFC 8949) needed for the structures above

const List<int> _cborNull = [0xF6];

List<int> _cborHead(int major, int value) => switch (value) {
      < 24 => [major << 5 | value],
      < 0x100 => [major << 5 | 24, value],
      < 0x10000 => [major << 5 | 25, value >> 8, value & 0xFF],
      _ => [major << 5 | 26, value >> 24 & 0xFF, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF],
    };

List<int> _cborUint(int value) => _cborHead(0, value);

List<int> _cborBytes(List<int> bytes) => [..._cborHead(2, bytes.length), ...bytes];

List<int> _cborText(String text) {
  final bytes = utf8.encode(text);
  return [..._cborHead(3, bytes.length), ...bytes];
}

List<int> _cborArray(List<List<int>> items) => [
      ..._cborHead(4, items.length),
      for (final item in items) ...item,
    ];

// CoAP over UDP (RFC 7252), as far as one request with OSCORE needs it

class CoapOption {
  final int number;
  final List<int> value;

  const CoapOption(this.number, this.value);
}

class CoapMessage {
  static const int confirmable = 0;
  static const int nonConfirmable = 1;
  static const int acknowledgement = 2;
  static const int reset = 3;

  final int type;
  final int code;
  final int messageId;
  final List<int> token;
  final List<CoapOption> options;
  final List<int> payload;

  const CoapMessage({
    required this.type,
    required this.code,
    required this.messageId,
    this.token = const [],
    this.options = const [],
    this.payload = const [],
  });

  List<int>? option(int number) {
    for (final option in options) {
      if (option.number == number) return option.value;
    }
    return null;
  }

  Uint8List encode() => Uint8List.fromList([
        0x40 | type << 4 | token.length,
        code,
        messageId >> 8,
        messageId & 0xFF,
        ...token,
        ...encodeCoapOptions(options),
        if (payload.isNotEmpty) ...[0xFF, ...payload],
      ]);

  // Null for anything that isn't a CoAP message
  static CoapMessage? tryDecode(Uint8List data) {
    if (data.length < 4 || data[0] >> 6 != 1) return null;
    final tokenLength = data[0] & 0x0F;
    if (tokenLength > 8 || data.length < 4 + tokenLength) return null;
    try {
      final (options, payloadStart) = decodeCoapOptions(data, 4 + tokenLength);
      return CoapMessage(
        type: data[0] >> 4 & 0x03,
        code: data[1],
        messageId: data[2] << 8 | data[3],
        token: data.sublist(4, 4 + tokenLength),
        options: options,
        payload: data.sublist(payloadStart),
      );
    } on FormatException {
      return null;
    }
  }
}

// Options sorted by number, each with the delta to the previous one
List<int> encodeCoapOptions(List<CoapOption> options) {
  final sorted = [...options]..sort((a, b) => a.number.compareTo(b.number));
  final bytes = <int>[];
  var previous = 0;
  for (final option in sorted) {
    final (deltaNibble, deltaExtra) = _optionNibble(option.number - previous);
    final (lengthNibble, lengthExtra) = _optionNibble(option.value.length);
    bytes
      ..add(deltaNibble << 4 | lengthNibble)
      ..addAll(deltaExtra)
      ..addAll(lengthExtra)
      ..addAll(option.value);
    previous = option.number;
  }
  return bytes;
}

(int, List<int>) _optionNibble(int value) => switch (value) {
      < 13 => (value, const []),
      < 269 => (13, [value - 13]),
      _ => (14, [(value - 269) >> 8, (value - 269) & 0xFF]),
    };

// Reads options from [start] up to the payload marker. Returns them and where
// the payload starts
(List<CoapOption>, int) decodeCoapOptions(List<int> data, int start) {
  final options = <CoapOption>[];
  var index = start;
  var number = 0;
  int read() {
    if (index >= data.length) throw const FormatException('Truncated option');
    return data[index++];
  }

  int extended(int nibble) => switch (nibble) {
        13 => read() + 13,
        14 => (read() << 8 | read()) + 269,
        15 => throw const FormatException('Reserved option nibble'),
        _ => nibble,
      };

  while (index < data.length) {
    final first = read();
    if (first == 0xFF) return (options, index);
    number += extended(first >> 4);
    final length = extended(first & 0x0F);
    if (index + length > data.length) throw const FormatException('Truncated option');
    options.add(CoapOption(number, data.sublist(index, index + length)));
    index += length;
  }
  return (options, index);
}

final Random _random = Random.secure();

Uint8List _randomBytes(int length) =>
    Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

// Retransmission parameters of RFC 7252 4.8
const Duration _ackTimeout = Duration(seconds: 2);
const int _maxRetransmit = 4;
const Duration _maxTransmitWait = Duration(seconds: 93);

// Sends a confirmable [request] and waits for its response, piggybacked on
// the ACK or sent separately after an empty ACK. Retransmits until the
// device acknowledges it
Future<CoapMessage> coapExchange(
  InternetAddress address,
  int port,
  CoapMessage request, {
  required Duration timeout,
}) async {
  final socket = await RawDatagramSocket.bind(
    address.type == InternetAddressType.IPv6 ? InternetAddress.anyIPv6 : InternetAddress.anyIPv4,
    0,
  );
  final response = Completer<CoapMessage>();
  final bytes = request.encode();
  var acknowledged = false;
  var retransmissions = 0;
  // Initial timeout randomised between 1 and 1.5 times ACK_TIMEOUT
  var wait = _ackTimeout * (1 + _random.nextDouble() / 2);
  Timer? timer;

  void transmit() {
    socket.send(bytes, address, port);
    timer = Timer(wait, () {
      if (acknowledged || response.isCompleted) return;
      if (retransmissions == _maxRetransmit) {
        response.completeError(TimeoutException('No answer from the device', timeout));
        return;
      }
      retransmissions++;
      wait *= 2;
      transmit();
    });
  }

  socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final datagram = socket.receive();
    if (datagram == null || response.isCompleted) return;
    final message = CoapMessage.tryDecode(datagram.data);
    if (message == null) return;

    final sameId = message.messageId == request.messageId;
    if (message.type == CoapMessage.reset && sameId) {
      response.completeError(const OscoreException('The device rejected the message (RST)'));
      return;
    }
    if (message.type == CoapMessage.acknowledgement && sameId) {
      acknowledged = true;
      // Empty ACK: the response follows in its own message
      if (message.code == 0) return;
    }
    if (!_sameBytes(message.token, request.token) || message.code < 0x40) return;
    if (message.type == CoapMessage.confirmable) {
      socket.send(
        CoapMessage(type: CoapMessage.acknowledgement, code: 0, messageId: message.messageId)
            .encode(),
        datagram.address,
        datagram.port,
      );
    }
    response.complete(message);
  });

  try {
    transmit();
    return await response.future.timeout(timeout);
  } finally {
    timer?.cancel();
    socket.close();
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

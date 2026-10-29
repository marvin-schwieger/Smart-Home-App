import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

// The algorithms of an OSCORE security context (RFC 8613 3.1), named like in
// the COSE registry and in aiocoap. Both sides must use the same ones.
// Stored by label, so existing labels must not be renamed

// AEAD algorithm that encrypts and authenticates the messages.
// AES-CCM-16-64-128 is the default every OSCORE endpoint has to support. The
// others are the ones the EDHOC cipher suites (RFC 9528) hand over to OSCORE,
// plus AES-CCM with the long tag
enum OscoreAlgorithm {
  aesCcm(10, keyLength: 16, nonceLength: 13, tagLength: 8),
  aesCcmLongTag(30, keyLength: 16, nonceLength: 13, tagLength: 16),
  aesGcm128(1, keyLength: 16, nonceLength: 12, tagLength: 16),
  aesGcm256(3, keyLength: 32, nonceLength: 12, tagLength: 16),
  chaCha20Poly1305(24, keyLength: 32, nonceLength: 12, tagLength: 16);

  const OscoreAlgorithm(
    this.coseId, {
    required this.keyLength,
    required this.nonceLength,
    required this.tagLength,
  });

  // Names in the order of the values. A constant list, so the authentication
  // page can offer them as choices
  static const List<String> labels = [
    'AES-CCM-16-64-128',
    'AES-CCM-16-128-128',
    'A128GCM',
    'A256GCM',
    'ChaCha20/Poly1305',
  ];

  String get label => labels[index];

  // Number in the COSE registry, part of the key derivation and the AAD
  final int coseId;

  // In bytes
  final int keyLength;
  final int nonceLength;
  final int tagLength;

  // The nonce holds the Sender ID and 6 more bytes (RFC 8613 5.2)
  int get maxIdLength => nonceLength - 6;

  // The default for an empty or unknown label
  static OscoreAlgorithm byLabel(String label) =>
      values.firstWhere((a) => a.label == label, orElse: () => aesCcm);

  // Encrypts [input] and appends the tag, or checks the tag and decrypts.
  // Throws if the tag doesn't match
  Uint8List process(bool encrypt, Uint8List key, Uint8List nonce, Uint8List aad, Uint8List input) {
    final parameters = AEADParameters(KeyParameter(key), tagLength * 8, nonce, aad);
    return switch (this) {
      aesCcm || aesCcmLongTag => (CCMBlockCipher(AESEngine())..init(encrypt, parameters)).process(input),
      aesGcm128 || aesGcm256 => (GCMBlockCipher(AESEngine())..init(encrypt, parameters)).process(input),
      chaCha20Poly1305 => _processChaCha(encrypt, parameters, input),
    };
  }

  // process() of pointycastle's ChaCha20Poly1305 leaves out the tag (it never
  // calls doFinal), so the steps are done here
  static Uint8List _processChaCha(bool encrypt, AEADParameters parameters, Uint8List input) {
    final cipher = ChaCha20Poly1305(ChaCha7539Engine(), Poly1305())..init(encrypt, parameters);
    final output = Uint8List(cipher.getOutputSize(input.length));
    var length = cipher.processBytes(input, 0, input.length, output, 0);
    length += cipher.doFinal(output, length);
    return output.sublist(0, length);
  }
}

// Hash function of HKDF, which derives the keys from the Master Secret
// (RFC 8613 3.2.1). SHA-256 is the default, SHA-384 comes with the EDHOC
// suite of A256GCM
enum OscoreHkdf {
  sha256,
  sha384,
  sha512;

  // Names in the order of the values, see OscoreAlgorithm.labels
  static const List<String> labels = ['SHA-256', 'SHA-384', 'SHA-512'];

  String get label => labels[index];

  crypto.Hash get hash => switch (this) {
        sha256 => crypto.sha256,
        sha384 => crypto.sha384,
        sha512 => crypto.sha512,
      };

  // The default for an empty or unknown label
  static OscoreHkdf byLabel(String label) =>
      values.firstWhere((h) => h.label == label, orElse: () => sha256);

  // HKDF (RFC 5869). [length] is at most one hash long here, so one round of
  // the expand step is enough
  Uint8List derive(List<int> salt, List<int> secret, List<int> info, int length) {
    final prk = crypto.Hmac(hash, salt).convert(secret).bytes;
    final okm = crypto.Hmac(hash, prk).convert([...info, 1]).bytes;
    return Uint8List.fromList(okm.sublist(0, length));
  }
}

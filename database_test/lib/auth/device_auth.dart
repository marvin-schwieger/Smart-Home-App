import 'dart:convert';
import 'dart:typed_data';

import 'oscore_algorithms.dart';

// How the app proves to a device who it is, stored as JSON in the auth
// column of the device. The two most common methods per protocol:
// CoAP has DTLS, which secures the whole coaps:// connection, and OSCORE,
// which protects every single message. HTTP has Basic, username and
// password in every request, and OAuth 2.0, a token fetched from a token
// endpoint. Stored by name, so existing values must not be renamed
enum AuthMethod {
  none,
  // CoAP
  oscore,
  dtlsPsk,
  // HTTP
  basic,
  oauth2,
}

enum AuthInput {
  text,
  // Bytes, written as text or as hex with a 0x prefix, e.g. a key
  bytes,
  // Several lines, a certificate in PEM format
  pem,
  // One of [AuthField.options], empty means the first one
  choice,
}

// One setting of an authentication method, shown on the authentication page
class AuthField {
  final String key;
  final String label;
  final String? hint;
  final String? helper;
  final AuthInput input;

  // Hidden while typing, e.g. a password
  final bool secret;

  // Can be left empty
  final bool optional;

  // What can be picked for a choice, the first one is the default
  final List<String> options;

  const AuthField(
    this.key,
    this.label, {
    this.hint,
    this.helper,
    this.input = AuthInput.text,
    this.secret = false,
    this.optional = false,
    this.options = const [],
  });
}

class AuthType {
  final AuthMethod method;
  final String label;

  // One line in the list of methods
  final String subtitle;

  // Shown above the settings once the method is picked
  final String description;

  // URI schemes the method works with
  final Set<String> schemes;

  final List<AuthField> fields;

  const AuthType({
    required this.method,
    required this.label,
    required this.subtitle,
    required this.description,
    required this.schemes,
    this.fields = const [],
  });
}

const _bytesHelper = 'Text, or hex with a 0x prefix';

// Shown in this order on the authentication page
const List<AuthType> authTypes = [
  AuthType(
    method: AuthMethod.none,
    label: 'None',
    subtitle: 'No credentials are sent',
    description: 'Requests are sent without credentials.',
    schemes: {'coap', 'http', 'https'},
  ),
  AuthType(
    method: AuthMethod.dtlsPsk,
    label: 'DTLS',
    subtitle: 'Encrypted connection with a pre-shared key',
    description: 'Encrypted coaps:// connection. App and device know the same '
        'pre-shared key and prove it in the handshake (RFC 7252, PreSharedKey '
        'mode).',
    schemes: {'coaps'},
    fields: [
      AuthField('identity', 'IDENTITY', hint: 'e.g. app'),
      AuthField(
        'psk',
        'PRE-SHARED KEY',
        helper: _bytesHelper,
        input: AuthInput.bytes,
        secret: true,
      ),
    ],
  ),
  AuthType(
    method: AuthMethod.oscore,
    label: 'OSCORE',
    subtitle: 'Every message encrypted end-to-end',
    description: 'Encrypts and signs every CoAP message end-to-end with keys '
        'derived from a shared Master Secret (RFC 8613). Works over plain '
        'coap:// and through proxies.',
    schemes: {'coap'},
    fields: [
      AuthField(
        'masterSecret',
        'MASTER SECRET',
        hint: '0x0102030405060708090a0b0c0d0e0f10',
        helper: _bytesHelper,
        input: AuthInput.bytes,
        secret: true,
      ),
      AuthField(
        'masterSalt',
        'MASTER SALT',
        hint: '0x9e7ca92223786340',
        helper: 'Optional. $_bytesHelper',
        input: AuthInput.bytes,
        optional: true,
      ),
      AuthField(
        'senderId',
        'SENDER ID',
        hint: 'ID of the app, e.g. 0x01',
        helper: 'Up to 7 bytes, 6 with GCM and ChaCha20, may be empty. $_bytesHelper',
        input: AuthInput.bytes,
        optional: true,
      ),
      AuthField(
        'recipientId',
        'RECIPIENT ID',
        hint: 'ID of the device, e.g. 0x02',
        helper: 'Up to 7 bytes, 6 with GCM and ChaCha20, may be empty. $_bytesHelper',
        input: AuthInput.bytes,
        optional: true,
      ),
      AuthField(
        'idContext',
        'ID CONTEXT',
        helper: 'Optional. $_bytesHelper',
        input: AuthInput.bytes,
        optional: true,
      ),
      AuthField(
        'algorithm',
        'AEAD ALGORITHM',
        helper: 'Encrypts the messages. AES-CCM-16-64-128 is the default every '
            'device supports',
        input: AuthInput.choice,
        options: OscoreAlgorithm.labels,
      ),
      AuthField(
        'hkdf',
        'HKDF',
        helper: 'Hash that derives the keys from the Master Secret, SHA-256 is '
            'the default',
        input: AuthInput.choice,
        options: OscoreHkdf.labels,
      ),
    ],
  ),
  AuthType(
    method: AuthMethod.basic,
    label: 'Basic',
    subtitle: 'Username and password',
    description: 'Username and password in every request (RFC 7617). They '
        'are only encoded, not encrypted - use it over https://.',
    schemes: {'http', 'https'},
    fields: [
      AuthField('username', 'USERNAME'),
      AuthField('password', 'PASSWORD', secret: true),
    ],
  ),
  AuthType(
    method: AuthMethod.oauth2,
    label: 'OAuth 2.0',
    subtitle: 'Access token from a token endpoint',
    description: 'Gets an access token from a token endpoint with the client '
        'credentials grant (RFC 6749) and sends it as bearer token (RFC 6750). '
        'A new one is fetched when it expires or the device rejects it.',
    schemes: {'http', 'https'},
    fields: [
      AuthField(
        'tokenUrl',
        'TOKEN URL',
        hint: '/oauth/token',
        helper: 'A path is taken relative to the device',
      ),
      AuthField('clientId', 'CLIENT ID'),
      AuthField('clientSecret', 'CLIENT SECRET', secret: true),
      AuthField('scope', 'SCOPE', hint: 'e.g. read write', optional: true),
    ],
  ),
];

// Checking the certificate of the device on https://, for every method
const AuthField caCertField = AuthField(
  'caCert',
  'CA CERTIFICATE',
  hint: '-----BEGIN CERTIFICATE-----',
  helper: 'PEM, for devices with their own CA or a self-signed certificate. '
      'Empty: the CAs trusted by the system',
  input: AuthInput.pem,
  optional: true,
);

AuthType authType(AuthMethod method) => authTypes.firstWhere((t) => t.method == method);

List<AuthType> authTypesFor(String scheme) =>
    authTypes.where((t) => t.schemes.contains(scheme)).toList();

// Thrown when a request can't be sent because of the authentication, e.g.
// when the token endpoint rejects the client
class AuthException implements Exception {
  final String message;

  const AuthException(this.message);

  @override
  String toString() => message;
}

class DeviceAuth {
  final AuthMethod method;

  // Settings by the key of their field, see [authTypes]
  final Map<String, String> values;

  const DeviceAuth(this.method, [this.values = const {}]);

  static const DeviceAuth none = DeviceAuth(AuthMethod.none);

  // Falls back to no authentication if [json] can't be read, also for
  // methods that no longer exist
  factory DeviceAuth.decode(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return none;
      final method = AuthMethod.values.asNameMap()[decoded['method']] ?? AuthMethod.none;
      return DeviceAuth(method, {
        for (final MapEntry(:key, :value) in decoded.entries)
          if (key != 'method' && value != null) key: '$value',
      });
    } on FormatException {
      return none;
    }
  }

  String encode() => jsonEncode({'method': method.name, ...values});

  String operator [](String key) => values[key] ?? '';

  Uint8List bytes(String key) => parseBytes(this[key]);

  // Fields of the method, on https:// also the CA of the device
  List<AuthField> fieldsFor(String scheme) =>
      [...authType(method).fields, if (scheme == 'https') caCertField];

  DeviceAuth withValue(String key, String value) =>
      DeviceAuth(method, {...values, key: value});

  // The values of the other methods stay until saving, so switching back
  // and forth keeps what was typed
  DeviceAuth withMethod(AuthMethod method) => DeviceAuth(method, values);

  // Keeps the method if it works with [scheme], otherwise takes the first
  // one that does, e.g. DTLS when switching to coaps://
  DeviceAuth forScheme(String scheme) => authType(method).schemes.contains(scheme)
      ? this
      : withMethod(authTypesFor(scheme).first.method);

  // Only the settings of the method are stored, so no password typed for
  // another method stays in the database
  DeviceAuth cleanedFor(String scheme) => DeviceAuth(method, {
        for (final field in fieldsFor(scheme))
          if (values[field.key]?.isNotEmpty ?? false) field.key: values[field.key]!,
      });

  // Value of a choice field, its first option while nothing is picked
  String choice(AuthField field) {
    final value = this[field.key];
    return field.options.contains(value) ? value : field.options.first;
  }

  // One line for the device sheet, e.g. "User admin"
  String get summary => switch (method) {
        AuthMethod.none => 'No credentials are sent',
        AuthMethod.dtlsPsk => 'Identity ${this['identity']}',
        AuthMethod.oscore => '${OscoreAlgorithm.byLabel(this['algorithm']).label} · '
            'recipient ID ${_orEmpty(this['recipientId'])}, '
            'sender ID ${_orEmpty(this['senderId'])}',
        AuthMethod.basic => 'User ${this['username']}',
        AuthMethod.oauth2 => 'Client ${this['clientId']}',
      };

  // Error text if a setting is missing or can't work, null if it can be saved
  String? validate(String scheme) {
    if (!authType(method).schemes.contains(scheme)) {
      return 'Pick an authentication for $scheme://';
    }
    for (final field in fieldsFor(scheme)) {
      final value = this[field.key].trim();
      if (value.isEmpty) {
        if (field.optional || field.input == AuthInput.choice) continue;
        return 'Fill in ${field.label.toLowerCase()}';
      }
      if (field.input == AuthInput.bytes && tryParseBytes(value) == null) {
        return '${_capitalized(field.label)}: odd or invalid hex';
      }
      if (field.input == AuthInput.pem && !value.contains('-----BEGIN ')) {
        return '${_capitalized(field.label)} is not in PEM format';
      }
      if (field.input == AuthInput.choice && !field.options.contains(value)) {
        return '${_capitalized(field.label)}: $value is not supported';
      }
    }
    if (method == AuthMethod.oscore) {
      final sender = bytes('senderId');
      final recipient = bytes('recipientId');
      final algorithm = OscoreAlgorithm.byLabel(this['algorithm']);
      final maxLength = algorithm.maxIdLength;
      if (sender.length > maxLength || recipient.length > maxLength) {
        return 'Sender and recipient ID can have at most $maxLength bytes with ${algorithm.label}';
      }
      if (_sameBytes(sender, recipient)) return 'Sender and recipient ID must differ';
    }
    if (method == AuthMethod.oauth2) {
      final url = Uri.tryParse(this['tokenUrl'].trim());
      if (url == null || (url.hasScheme && !url.isScheme('http') && !url.isScheme('https'))) {
        return 'The token URL must be an http(s):// URL or a path';
      }
    }
    return null;
  }
}

// "0x0a0b" are the bytes 10 and 11, anything else is taken as UTF-8 text.
// Returns null for invalid hex
Uint8List? tryParseBytes(String text) {
  final trimmed = text.trim();
  if (!trimmed.toLowerCase().startsWith('0x')) return utf8.encode(text);
  final hex = trimmed.substring(2).replaceAll(RegExp(r'[\s:]'), '');
  if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(hex)) return null;
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

Uint8List parseBytes(String text) => tryParseBytes(text) ?? Uint8List(0);

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _orEmpty(String id) => id.isEmpty ? 'empty' : id;

String _capitalized(String label) =>
    '${label[0].toUpperCase()}${label.substring(1).toLowerCase()}';

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'device_auth.dart';

// Sends one HTTP request with the authentication of the device. OAuth may
// need a second request when the device no longer accepts the cached token.
// [client] is for tests, otherwise one is created for the request, set up
// with the CA of the device
Future<http.Response> sendHttpRequest(
  String method,
  Uri uri,
  String payload,
  DeviceAuth auth, {
  http.Client? client,
}) async {
  final httpClient = client ?? _clientFor(auth, uri);
  try {
    Future<http.Response> send(Map<String, String> headers) =>
        _send(httpClient, method, uri, payload, headers);

    // Awaited here, so the client stays open for a second request
    return await switch (auth.method) {
      AuthMethod.basic => send({'Authorization': basicAuthorization(auth['username'], auth['password'])}),
      AuthMethod.oauth2 => _sendOAuth(httpClient, send, uri, auth),
      _ => send({}),
    };
  } finally {
    if (client == null) httpClient.close();
  }
}

// On https:// with a CA of its own, only certificates signed by it are
// trusted, otherwise those the system trusts
http.Client _clientFor(DeviceAuth auth, Uri uri) {
  final caCert = auth['caCert'].trim();
  if (!uri.isScheme('https') || caCert.isEmpty) return http.Client();

  final context = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(utf8.encode(caCert));
  return IOClient(HttpClient(context: context));
}

Future<http.Response> _send(
  http.Client client,
  String method,
  Uri uri,
  String payload,
  Map<String, String> headers,
) async {
  final request = http.Request(method, uri)..headers.addAll(headers);
  // GET has no body, see methodHasPayload in request.dart
  if (method != 'GET') request.body = payload;
  return http.Response.fromStream(await client.send(request));
}

// Basic (RFC 7617)

String basicAuthorization(String user, String password) =>
    'Basic ${base64.encode(utf8.encode('$user:$password'))}';

// OAuth 2.0 client credentials grant (RFC 6749 4.4)

class _Token {
  final String value;

  // Null if the token endpoint gave no lifetime, then it is used until the
  // device rejects it
  final DateTime? expires;

  const _Token(this.value, this.expires);

  bool get isValid => expires == null || DateTime.now().isBefore(expires!);
}

// Access tokens by token endpoint and client, shared by all devices using them
final Map<String, _Token> _tokens = {};

// Fetched a bit before the token really expires, so it can't run out on the
// way to the device. At most half of its lifetime
const Duration _expiryMargin = Duration(seconds: 30);

Future<http.Response> _sendOAuth(
  http.Client client,
  Future<http.Response> Function(Map<String, String> headers) send,
  Uri uri,
  DeviceAuth auth,
) async {
  final tokenUrl = uri.resolve(auth['tokenUrl'].trim());
  final key = [tokenUrl, auth['clientId'], auth['clientSecret'], auth['scope']].join('\n');

  final cached = _tokens[key];
  final token = cached != null && cached.isValid ? cached : await _fetchToken(client, tokenUrl, auth);
  _tokens[key] = token;
  final response = await send({'Authorization': 'Bearer ${token.value}'});

  // The device forgot the token, e.g. after a restart: one more try with a
  // new one
  if (response.statusCode != 401 || token != cached) return response;
  final fresh = _tokens[key] = await _fetchToken(client, tokenUrl, auth);
  return send({'Authorization': 'Bearer ${fresh.value}'});
}

Future<_Token> _fetchToken(http.Client client, Uri tokenUrl, DeviceAuth auth) async {
  final scope = auth['scope'].trim();
  // The client authenticates with HTTP Basic, which every token endpoint
  // must support (RFC 6749 2.3.1). Both parts are form encoded first
  final response = await client.post(
    tokenUrl,
    headers: {
      'Authorization': basicAuthorization(
        Uri.encodeQueryComponent(auth['clientId']),
        Uri.encodeQueryComponent(auth['clientSecret']),
      ),
      'Accept': 'application/json',
    },
    body: {'grant_type': 'client_credentials', if (scope.isNotEmpty) 'scope': scope},
  );

  final Object? body;
  try {
    body = jsonDecode(response.body);
  } on FormatException {
    throw AuthException('Token endpoint answered ${response.statusCode} without JSON');
  }
  if (response.statusCode != 200 || body is! Map<String, dynamic>) {
    final error = body is Map<String, dynamic> ? body['error'] : null;
    throw AuthException('Token endpoint answered ${response.statusCode}${error == null ? '' : ': $error'}');
  }
  final value = body['access_token'];
  final type = body['token_type'];
  if (value is! String || value.isEmpty) throw const AuthException('Token endpoint sent no access_token');
  if (type is String && type.toLowerCase() != 'bearer') {
    throw AuthException('Token type $type is not supported, only Bearer');
  }
  final lifetime = body['expires_in'];
  if (lifetime is! num) return _Token(value, null);
  final seconds = lifetime.toInt();
  final margin = min(_expiryMargin.inSeconds, seconds ~/ 2);
  return _Token(value, DateTime.now().add(Duration(seconds: seconds - margin)));
}

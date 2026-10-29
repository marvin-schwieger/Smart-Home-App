import 'dart:convert';

import 'package:coap/coap.dart';

import 'auth/coap_security.dart';
import 'auth/device_auth.dart';
import 'auth/http_auth.dart';
import 'database.dart';

const List<String> requestMethods = ['GET', 'POST', 'PUT', 'DELETE'];

// coaps:// and https:// are the secured variants, see auth/device_auth.dart
// for the authentication that fits each of them
const List<String> schemes = ['coap', 'coaps', 'http', 'https'];

// GET has no body, so the payload field is only shown for the other methods!
bool methodHasPayload(String method) => method != 'GET';

// A path is always stored with a leading slash
String normalizePath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return '/';
  return trimmed.startsWith('/') ? trimmed : '/$trimmed';
}

// Does not work correctly for now -> leads to crashes when editing host name
Uri buildUri(String scheme, String host, String path) =>
    Uri.parse('$scheme://${host.trim()}${normalizePath(path)}');

bool _usesHttp(Device device) => device.scheme == 'http' || device.scheme == 'https';

// Sends the device's request with its authentication and returns the status
// code and the raw body, throws if the request fails. Sensors read their
// values from the body. Without [timeout] a CoAP request to an unreachable
// device only fails after all retransmissions from coap_config_all.yaml,
// which takes over 25 minutes
Future<({String code, String body})> fetchResponse(
  Device device, {
  Duration? timeout,
}) async {
  var uri = buildUri(device.scheme, device.host, device.path);
  final auth = DeviceAuth.decode(device.auth);

  if (_usesHttp(device)) {
    final request = sendHttpRequest(device.method, uri, device.payload, auth);
    final response = await (timeout == null ? request : request.timeout(timeout));
    return (code: '${response.statusCode}', body: response.body);
  }

  // CoAP: fall back to the default port 5683, 5684 for coaps://, if the host
  // has none
  if (!uri.hasPort) uri = uri.replace(port: device.scheme == 'coaps' ? 5684 : 5683);
  if (auth.method == AuthMethod.oscore) {
    final payload = methodHasPayload(device.method) ? device.payload : '';
    return fetchOscore(device.method, uri, auth, payload, timeout: timeout);
  }

  final client = coapClient(uri, auth);
  try {
    final request = switch (device.method) {
      'POST' => client.post(uri, payload: device.payload),
      'PUT' => client.put(uri, payload: device.payload),
      // Only the raw request carries a body on DELETE.
      'DELETE' => client.send(
          CoapRequest.delete(uri, payload: utf8.encode(device.payload)),
        ),
      _ => client.get(uri),
    };
    final response = await (timeout == null ? request : request.timeout(timeout));
    return (code: '${response.code}', body: response.payloadString);
  } finally {
    // Also stops the retransmissions of a request that ran into the timeout
    client.close();
  }
}

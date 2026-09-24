import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import 'database.dart';
import 'device_data.dart';
import 'request.dart';

// One response of a sensor, decoded once so every widget can read its field
class Sample {
  final DateTime time;

  // JSON value of the body, or the trimmed text if it isn't JSON
  final Object? data;

  const Sample(this.time, this.data);
}

// Link between the app and one device, shared by all widgets on its page.
// A sensor is polled in its interval for the whole app session and keeps the
// samples in memory only - they survive leaving the page, but not an app
// restart. An actuator sends its payload whenever a widget changes it
class DeviceSession extends ChangeNotifier {
  static const int defaultPollSeconds = 5;

  // Oldest samples are dropped beyond this, so memory can't grow forever
  static const int maxSamples = 600;

  // A poll is given up after one interval, but at least after this, so a
  // lost CoAP packet still gets a retransmission (ackTimeout is 3 s)
  static const int minTimeoutSeconds = 5;

  // Commands of actuators, without it an unreachable CoAP device only fails
  // after all retransmissions, which takes over 25 minutes
  static const Duration sendTimeout = Duration(seconds: 10);

  final List<Sample> samples = [];

  // Body of the last response or the error, null until something was sent
  String? lastResponse;
  String? lastCode;
  bool lastFailed = false;
  Duration? lastElapsed;

  Device _device;
  Timer? _timer;
  bool _polling = false;
  bool _disposed = false;

  // Numbers the requests so a slow old response can't overwrite a newer one
  int _requestCount = 0;

  DeviceSession(this._device) {
    if (isSensor) _restartPolling();
  }

  Device get device => _device;

  bool get isSensor => _device.role == DeviceRole.sensor;

  Sample? get latest => samples.isEmpty ? null : samples.last;

  int get pollSeconds => _device.pollSeconds ?? defaultPollSeconds;

  // Current value of [field] in the payload, what the actuator controls show
  Object? payloadValue(String field) => readField(decodeBody(_device.payload), field);

  // Takes over edited values; polling only restarts if the interval changed
  void update(Device device) {
    final intervalChanged = device.pollSeconds != _device.pollSeconds;
    _device = device;
    if (isSensor && intervalChanged) _restartPolling();
    _notify();
  }

  Future<void> setPollSeconds(int seconds) async {
    // Saved first, otherwise going back right away could let the room page
    // show the old interval
    await (database.update(database.devices)..where((t) => t.id.equals(_device.id)))
        .write(DevicesCompanion(pollSeconds: Value(seconds)));
    update(_device.copyWith(pollSeconds: Value(seconds)));
  }

  // Sets [field] of the payload to [value], saves it and sends it, e.g. the
  // brightness of a lamp. See writeField for how the field is written
  Future<void> write(String field, Object value) async {
    final payload = writeField(_device.payload, field, value);
    _device = _device.copyWith(payload: payload);
    _notify(); // the controls show the new state right away
    await (database.update(database.devices)..where((t) => t.id.equals(_device.id)))
        .write(DevicesCompanion(payload: Value(payload)));
    await send();
  }

  // Sends one request with the stored payload, or with [payload] instead
  Future<void> send({String? payload}) async {
    final request = ++_requestCount;
    lastResponse = 'Sending...';
    lastCode = null;
    lastFailed = false;
    lastElapsed = null;
    _notify();

    final device = payload == null ? _device : _device.copyWith(payload: payload);
    await _request(device, sendTimeout, isCurrent: () => request == _requestCount);
    _notify();
  }

  void _restartPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: pollSeconds), (_) => _poll());
    _poll(); // first reading right away instead of after one interval
  }

  Future<void> _poll() async {
    // A slow request must not pile up behind the timer, so a tick is skipped
    // while the previous one is running
    if (_polling) return;
    _polling = true;
    final body = await _request(
      _device,
      Duration(seconds: max(pollSeconds, minTimeoutSeconds)),
    );
    _polling = false;

    if (body != null) {
      samples.add(Sample(DateTime.now(), decodeBody(body)));
      if (samples.length > maxSamples) samples.removeAt(0);
    }
    _notify();
  }

  // Sends the request of [device] and keeps the outcome in the last* fields,
  // unless [isCurrent] says a newer request has started. Returns the body,
  // null if the request failed
  Future<String?> _request(
    Device device,
    Duration timeout, {
    bool Function()? isCurrent,
  }) async {
    final stopwatch = Stopwatch()..start();
    String? body;
    String? code;
    String text;
    try {
      final response = await fetchResponse(device, timeout: timeout);
      body = response.body;
      code = response.code;
      text = body.isEmpty ? 'Empty response' : body;
    } on TimeoutException {
      text = 'No response within ${formatSeconds(timeout.inSeconds)}';
    } catch (e) {
      text = 'Error: $e';
    }

    if (isCurrent == null || isCurrent()) {
      lastResponse = text;
      lastCode = code;
      lastFailed = body == null;
      lastElapsed = stopwatch.elapsed;
    }
    return body;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

// One session per device id, running for the whole app session
final Map<int, DeviceSession> _sessions = {};

// Returns the running session of [device] or starts one; a sensor starts
// polling here. Edits don't reach a running session this way, see
// updateDeviceSession
DeviceSession deviceSession(Device device) =>
    _sessions.putIfAbsent(device.id, () => DeviceSession(device));

// Hands the edited [device] to its running session, if there is one
void updateDeviceSession(Device device) => _sessions[device.id]?.update(device);

// Called when the device is deleted
void closeDeviceSession(int deviceId) => _sessions.remove(deviceId)?.dispose();

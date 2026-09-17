import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:fl_chart/fl_chart.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'database.dart';
import 'request.dart';

// Predefined devices: the entries of the "Add a device" list and the
// ready-made pages of each preset (lamp and temperature sensor)

const Color _fieldColor = Color(0xFFEDE9E3);
const Color _subtitleColor = Color(0xFF8D6E4A);

// One entry of the "Add a device" list
class DeviceTemplate {
  final DeviceKind kind;
  final String group;
  final String label;
  final IconData icon;

  // Transport that is preselected in the address form
  final String scheme;

  const DeviceTemplate({
    required this.kind,
    required this.group,
    required this.label,
    required this.icon,
    required this.scheme,
  });

  String get subtitle => '$scheme://${kind.fixedMethod ?? 'any verb'}';
}

// Shown grouped in this order
const List<DeviceTemplate> deviceTemplates = [
  DeviceTemplate(
    kind: DeviceKind.temperature,
    group: 'Sensors',
    label: 'Temperature',
    icon: Icons.thermostat,
    scheme: 'coap',
  ),
  DeviceTemplate(
    kind: DeviceKind.lamp,
    group: 'Lights',
    label: 'Smart lamp',
    icon: Icons.lightbulb_outline,
    scheme: 'coap',
  ),
  DeviceTemplate(
    kind: DeviceKind.custom,
    group: 'Anything with an address',
    label: 'HTTP endpoint',
    icon: Icons.language,
    scheme: 'http',
  ),
  DeviceTemplate(
    kind: DeviceKind.custom,
    group: 'Anything with an address',
    label: 'CoAP resource',
    icon: Icons.router_outlined,
    scheme: 'coap',
  ),
];

extension DeviceKindPreset on DeviceKind {
  // Used in the sheet title, null for custom resources
  String? get label => switch (this) {
        DeviceKind.lamp => 'smart lamp',
        DeviceKind.temperature => 'temperature sensor',
        DeviceKind.custom => null,
      };

  // Presets always send with the same method, custom resources let the user pick
  String? get fixedMethod => switch (this) {
        DeviceKind.lamp => 'PUT',
        DeviceKind.temperature => 'GET',
        DeviceKind.custom => null,
      };

  // Payload a newly created device starts with
  String get initialPayload => switch (this) {
        DeviceKind.lamp => const LampState().toPayload(),
        DeviceKind.temperature || DeviceKind.custom => '',
      };

  // Polling interval a newly created device starts with, null if it doesn't poll
  int? get defaultPollSeconds => switch (this) {
        DeviceKind.temperature => 5,
        DeviceKind.lamp || DeviceKind.custom => null,
      };
}

// State of a lamp. It is stored as the device payload, so the last sent
// command is also what the controls show when the page is opened again
class LampState {
  final bool on;

  // 0 - 100 percent
  final int brightness;

  // As picked in the colour dialog, [brightness] is sent separately
  final Color color;

  const LampState({
    this.on = true,
    this.brightness = 100,
    this.color = const Color(0xFFFFFFFF),
  });

  // Falls back to the defaults if the payload is empty or not valid JSON
  factory LampState.fromPayload(String payload) {
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      final hex = (json['color'] as String).replaceFirst('#', '');
      return LampState(
        on: json['on'] as bool,
        brightness: (json['brightness'] as num).round().clamp(0, 100),
        color: Color(0xFF000000 | int.parse(hex, radix: 16)),
      );
    } catch (_) {
      return const LampState();
    }
  }

  String get hex => colorHex(color);

  String toPayload() =>
      jsonEncode({'on': on, 'brightness': brightness, 'color': hex});

  LampState copyWith({bool? on, int? brightness, Color? color}) => LampState(
        on: on ?? this.on,
        brightness: brightness ?? this.brightness,
        color: color ?? this.color,
      );
}

// e.g. #FFAA00
String colorHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

// Bulb filled with the lamp colour, greyed out while the lamp is off
class LampIcon extends StatelessWidget {
  final LampState state;
  final double size;

  const LampIcon({super.key, required this.state, this.size = 24});

  @override
  Widget build(BuildContext context) {
    // Dark icon on light colours, white icon on dark ones
    final iconColor =
        ThemeData.estimateBrightnessForColor(state.color) == Brightness.dark
            ? Colors.white
            : Colors.black87;

    return Container(
      padding: EdgeInsets.all(size / 2.5),
      decoration: BoxDecoration(
        color: state.on ? state.color : _fieldColor,
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: Colors.black12),
      ),
      child: Icon(
        state.on ? Icons.lightbulb : Icons.lightbulb_outline,
        size: size,
        color: state.on ? iconColor : Colors.black38,
      ),
    );
  }
}

// Control page of a lamp: on/off, brightness and colour. Every change is saved
// and sent right away as a PUT with the lamp state as JSON payload
class LampPage extends StatefulWidget {
  final Device device;
  final Room room;

  const LampPage({super.key, required this.device, required this.room});

  @override
  State<LampPage> createState() => _LampPageState();
}

class _LampPageState extends State<LampPage> {
  late Device _device;
  late LampState _state;

  // Result of the last request, null until something was sent
  String? _response;
  Duration? _elapsed;

  // Numbers the requests so a slow old response can't overwrite a newer one
  int _requestCount = 0;

  @override
  void initState() {
    super.initState();
    _device = widget.device;
    _state = LampState.fromPayload(_device.payload);
  }

  Future<void> _apply(LampState state) async {
    final payload = state.toPayload();
    final request = ++_requestCount;
    setState(() {
      _state = state;
      _device = _device.copyWith(payload: payload);
      _response = 'Sending...';
      _elapsed = null;
    });

    await (database.update(database.devices)
          ..where((t) => t.id.equals(_device.id)))
        .write(DevicesCompanion(payload: Value(payload)));

    final stopwatch = Stopwatch()..start();
    final response = await sendRequest(_device);
    if (!mounted || request != _requestCount) return;
    setState(() {
      _response = response;
      _elapsed = stopwatch.elapsed;
    });
  }

  // Colour popup from flex_color_picker: a wheel for any colour plus the
  // Material colours as presets. Cancel returns the start colour unchanged
  Future<void> _pickColor() async {
    final color = await showColorPickerDialog(
      context,
      _state.color,
      title: Text('Pick a colour', style: Theme.of(context).textTheme.titleLarge),
      pickersEnabled: const {
        ColorPickerType.wheel: true,
        ColorPickerType.primary: true,
        ColorPickerType.accent: false,
      },
      pickerTypeLabels: const {
        ColorPickerType.wheel: 'Wheel',
        ColorPickerType.primary: 'Presets',
      },
      wheelDiameter: 240,
      wheelWidth: 20,
      showColorCode: true, // hex field, also accepts a typed code
      colorCodeHasColor: true,
      // Same #RRGGBB format as in the payload instead of the Dart 0xAARRGGBB
      copyPasteBehavior: const ColorPickerCopyPasteBehavior(
        copyFormat: ColorPickerCopyFormat.numHexRRGGBB,
      ),
      actionButtons: const ColorPickerActionButtons(
        dialogOkButtonLabel: 'Apply',
        dialogOkButtonType: ColorPickerActionButtonType.filled,
      ),
      constraints: const BoxConstraints(minWidth: 320, maxWidth: 320),
    );
    if (color != _state.color) await _apply(_state.copyWith(color: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_device.name),
            Text(
              'Smart lamp · ${widget.room.name}',
              style: const TextStyle(fontSize: 12, color: _subtitleColor),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(child: _controls()),
          const SizedBox(height: 20),
          _CommandSection(
            device: _device,
            payload: _state.toPayload(),
            response: _response,
            elapsed: _elapsed,
            placeholder: 'Nothing sent yet - change a control above',
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            LampIcon(state: _state, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _state.on ? 'On' : 'Off',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_state.brightness}% · ${_state.hex}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: _subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _state.on,
              onChanged: (on) => _apply(_state.copyWith(on: on)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Brightness', style: TextStyle(color: _subtitleColor)),
            Text(
              '${_state.brightness}%',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Slider(
          value: _state.brightness.toDouble(),
          max: 100,
          divisions: 100,
          // Only the preview follows while dragging, the request is sent on release
          onChanged: (value) =>
              setState(() => _state = _state.copyWith(brightness: value.round())),
          onChangeEnd: (value) =>
              _apply(_state.copyWith(brightness: value.round())),
        ),
        const SizedBox(height: 8),
        const Text('Colour', style: TextStyle(color: _subtitleColor)),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickColor,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _fieldColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _ColorDot(color: _state.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _state.hex,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                Text(
                  'Pick colour',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary),
                ),
                const Icon(Icons.chevron_right, color: Colors.black45),
              ],
            ),
          ),
        ),
      ],
    );
  }

}

// Bottom block of a device page: the request the page sends (method, URI and
// payload if it has one) and the result of the last request
class _CommandSection extends StatelessWidget {
  final Device device;
  final String? payload;
  final String? response;
  final Duration? elapsed;

  // Shown while [response] is null
  final String placeholder;

  const _CommandSection({
    required this.device,
    this.payload,
    required this.response,
    required this.elapsed,
    required this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final status = switch (response) {
      null => placeholder,
      final response when elapsed == null => response,
      final response => '$response · ${elapsed!.inMilliseconds} ms',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'COMMAND',
          style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: _subtitleColor),
        ),
        const SizedBox(height: 8),
        _Section(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDEBFF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      device.method,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      buildUri(device.scheme, device.host, device.path).toString(),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                  ),
                ],
              ),
              if (payload != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _fieldColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    payload!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(status, style: const TextStyle(fontSize: 13, color: _subtitleColor)),
            ],
          ),
        ),
      ],
    );
  }
}


// TEMP SENSORS
class TemperatureReading {
  final DateTime time;
  final double celsius;

  const TemperatureReading(this.time, this.celsius);
}

// Accepts a plain number ("21.5") or JSON with a "temperature", "temp" or
// "value" field, e.g. {"temperature": 21.5, "unit": "°C"} from the simulator
double? parseTemperature(String body) {
  final text = body.trim();
  final plain = double.tryParse(text);
  if (plain != null) return plain;
  try {
    final json = jsonDecode(text);
    if (json is Map) {
      for (final key in ['temperature', 'temp', 'value']) {
        final value = json[key];
        if (value is num) return value.toDouble();
      }
    }
  } catch (_) {
    // not JSON either
  }
  return null;
}

// Polls one temperature sensor in its interval and keeps the readings in
// memory only - they survive leaving the page, but not an app restart
class TemperatureFeed extends ChangeNotifier {
  // Oldest readings are dropped beyond this, so memory can't grow forever
  static const int maxReadings = 600;

  final List<TemperatureReading> readings = [];

  // Raw body of the last response, or the error if the last poll failed
  String? lastResponse;
  bool lastFailed = false;
  Duration? lastElapsed;

  Device _device;
  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  TemperatureFeed(this._device) {
    _restart();
  }

  TemperatureReading? get latest => readings.isEmpty ? null : readings.last;

  int get pollSeconds => _device.pollSeconds ?? DeviceKind.temperature.defaultPollSeconds!;

  // Takes over edited values; the timer only restarts if the interval changed
  void update(Device device) {
    final intervalChanged = device.pollSeconds != _device.pollSeconds;
    _device = device;
    if (intervalChanged) _restart();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: pollSeconds), (_) => _poll());
    _poll(); // first reading right away instead of after one interval
  }

  // A reading is given up after one interval, but at least after this, so a
  // lost CoAP packet still gets a retransmission (ackTimeout is 3 s)
  static const int minTimeoutSeconds = 5;

  Future<void> _poll() async {
    // A slow request must not pile up behind the timer, so a tick is skipped
    // while the previous one is running
    if (_busy) return;
    _busy = true;
    final stopwatch = Stopwatch()..start();
    final timeout = Duration(seconds: max(pollSeconds, minTimeoutSeconds));

    try {
      final response = await fetchResponse(_device, timeout: timeout);
      final celsius = parseTemperature(response.body);
      lastResponse = response.body.isEmpty ? 'Empty response (Code: ${response.code})' : response.body;
      lastFailed = celsius == null;
      if (celsius != null) {
        readings.add(TemperatureReading(DateTime.now(), celsius));
        if (readings.length > maxReadings) readings.removeAt(0);
      }
    } on TimeoutException {
      lastResponse = 'No response within ${formatSeconds(timeout.inSeconds)}';
      lastFailed = true;
    } catch (e) {
      lastResponse = 'Error: $e';
      lastFailed = true;
    } finally {
      _busy = false;
    }

    lastElapsed = stopwatch.elapsed;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

// One feed per sensor device id, running for the whole app session
final Map<int, TemperatureFeed> _feeds = {};

// Returns the running feed of [device] or starts one
TemperatureFeed temperatureFeed(Device device) {
  final feed = _feeds[device.id];
  if (feed == null) return _feeds[device.id] = TemperatureFeed(device);
  feed.update(device);
  return feed;
}

// Called when the device is deleted
void stopTemperatureFeed(int deviceId) => _feeds.remove(deviceId)?.dispose();

String formatCelsius(double celsius) => '${celsius.toStringAsFixed(1)} °C';

// e.g. 5 s, 1 min, 90 s
String formatSeconds(int seconds) =>
    seconds >= 60 && seconds % 60 == 0 ? '${seconds ~/ 60} min' : '$seconds s';

// e.g. 14:05:09
String _clock(DateTime time) =>
    [time.hour, time.minute, time.second].map((v) => '$v'.padLeft(2, '0')).join(':');

// Current temperature for the room list, rebuilt with every new reading
class TemperatureBadge extends StatelessWidget {
  final TemperatureFeed feed;

  const TemperatureBadge({super.key, required this.feed});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: feed,
      builder: (context, _) {
        final latest = feed.latest;
        return Text(
          latest == null ? '-- °C' : formatCelsius(latest.celsius),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            // Red while the sensor can't be read, the last value stays visible
            color: feed.lastFailed ? Colors.red.shade700 : Colors.black87,
          ),
        );
      },
    );
  }
}

// Page of a temperature sensor: current value, live chart and polling interval
class TemperatureSensorPage extends StatefulWidget {
  final Device device;
  final Room room;

  const TemperatureSensorPage({super.key, required this.device, required this.room});

  @override
  State<TemperatureSensorPage> createState() => _TemperatureSensorPageState();
}

class _TemperatureSensorPageState extends State<TemperatureSensorPage> {
  late Device _device = widget.device;
  late final TemperatureFeed _feed = temperatureFeed(_device);

  Future<void> _setInterval(int seconds) async {
    // Saved first, otherwise going back right away could let the room page
    // reload the old interval and reset the feed to it
    await (database.update(database.devices)
          ..where((t) => t.id.equals(_device.id)))
        .write(DevicesCompanion(pollSeconds: Value(seconds)));
    _device = _device.copyWith(pollSeconds: Value(seconds));
    _feed.update(_device); // restarts the timer with the new interval
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_device.name),
            Text(
              'Temperature sensor · ${widget.room.name}',
              style: const TextStyle(fontSize: 12, color: _subtitleColor),
            ),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: _feed,
        builder: (context, _) {
          final latest = _feed.latest;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Section(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDEBDD),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.thermostat, size: 28, color: Color(0xFFD9722B)),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              latest == null ? '-- °C' : formatCelsius(latest.celsius),
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              latest == null
                                  ? 'waiting for the first reading'
                                  : 'at ${_clock(latest.time)} · every ${formatSeconds(_feed.pollSeconds)}',
                              style: const TextStyle(fontSize: 12, color: _subtitleColor),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 220,
                      child: TemperatureChart(readings: _feed.readings),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Section(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Polling interval', style: TextStyle(color: _subtitleColor)),
                    const SizedBox(height: 8),
                    PollIntervalPicker(seconds: _feed.pollSeconds, onChanged: _setInterval),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _CommandSection(
                device: _device,
                response: _feed.lastResponse,
                elapsed: _feed.lastElapsed,
                placeholder: 'Waiting for the first response...',
              ),
            ],
          );
        },
      ),
    );
  }
}

// Line chart of the readings; x is the time in seconds, y the temperature
class TemperatureChart extends StatelessWidget {
  final List<TemperatureReading> readings;

  const TemperatureChart({super.key, required this.readings});

  @override
  Widget build(BuildContext context) {
    if (readings.length < 2) {
      return const Center(
        child: Text(
          'The chart starts after two readings',
          style: TextStyle(color: _subtitleColor),
        ),
      );
    }

    final color = Theme.of(context).colorScheme.primary;
    double x(DateTime time) => time.millisecondsSinceEpoch / 1000;
    DateTime time(double x) => DateTime.fromMillisecondsSinceEpoch((x * 1000).round());

    final temperatures = readings.map((r) => r.celsius);
    final minX = x(readings.first.time);
    final maxX = x(readings.last.time);

    return LineChart(
      duration: Duration.zero, // no animation, new points come in constantly
      LineChartData(
        minX: minX,
        maxX: maxX,
        // One degree of headroom so the line never touches the edges
        minY: (temperatures.reduce(min) - 1).floorToDouble(),
        maxY: (temperatures.reduce(max) + 1).ceilToDouble(),
        lineBarsData: [
          LineChartBarData(
            spots: [for (final r in readings) FlSpot(x(r.time), r.celsius)],
            isCurved: true,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.12)),
          ),
        ],
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text('${meta.formattedValue}°', style: const TextStyle(fontSize: 11)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              // Three time labels, the edges are left out so they don't overlap
              interval: max((maxX - minX) / 3, 1),
              minIncluded: false,
              maxIncluded: false,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(_clock(time(value)), style: const TextStyle(fontSize: 11)),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.black87,
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  '${formatCelsius(spot.y)}\n${_clock(time(spot.x))}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Preset intervals plus "Custom", which asks for any number of seconds
class PollIntervalPicker extends StatelessWidget {
  static const List<int> presets = [1, 5, 30, 60];

  final int seconds;
  final ValueChanged<int> onChanged;

  const PollIntervalPicker({super.key, required this.seconds, required this.onChanged});

  Future<void> _askCustom(BuildContext context) async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _CustomIntervalDialog(initial: seconds),
    );
    if (value != null) onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final isCustom = !presets.contains(seconds);

    return Row(
      children: [
        for (final preset in presets) ...[
          Expanded(
            child: _IntervalButton(
              label: formatSeconds(preset),
              selected: preset == seconds,
              onTap: () => onChanged(preset),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          flex: 2,
          child: _IntervalButton(
            label: isCustom ? formatSeconds(seconds) : 'Custom',
            selected: isCustom,
            onTap: () => _askCustom(context),
          ),
        ),
      ],
    );
  }
}

class _IntervalButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _IntervalButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primary : _fieldColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }
}

class _CustomIntervalDialog extends StatefulWidget {
  final int initial;

  const _CustomIntervalDialog({required this.initial});

  @override
  State<_CustomIntervalDialog> createState() => _CustomIntervalDialogState();
}

class _CustomIntervalDialogState extends State<_CustomIntervalDialog> {
  late final _ctrl = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int? get _seconds {
    final value = int.tryParse(_ctrl.text);
    return value != null && value >= 1 ? value : null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom interval'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: 'Every', suffixText: 'seconds'),
        onChanged: (_) => setState(() {}), // keeps the Apply button in sync
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _seconds == null ? null : () => Navigator.pop(context, _seconds),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

// White rounded card used for the blocks of the device pages
class _Section extends StatelessWidget {
  final Widget child;

  const _Section({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;

  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black12),
      ),
    );
  }
}

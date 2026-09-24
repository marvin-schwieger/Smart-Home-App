import 'package:flutter/material.dart';

import '../database.dart';
import '../device_session.dart';
import 'actuators/color.dart';
import 'actuators/send_button.dart';
import 'actuators/slider.dart';
import 'actuators/toggle.dart';
import 'response_view.dart';
import 'sensors/gauge.dart';
import 'sensors/line_chart.dart';
import 'sensors/poll_rate.dart';
import 'sensors/value_display.dart';
import 'widget_config.dart';

// All widgets that can be added to a device page. A new kind of widget needs
// a value in WidgetKind (database.dart), its view in sensors/ or actuators/
// and an entry in [widgetTypes] - the pickers and the settings sheet are
// built from that entry

enum ConfigInput {
  text,
  number,
  // Where a value is in the response or payload; the settings sheet suggests
  // the fields it finds in the last response
  field,
}

// One setting of a widget, shown as a text field in its settings sheet
class ConfigField {
  final String key;
  final String label;
  final String? hint;
  final ConfigInput input;

  const ConfigField(this.key, this.label, {this.hint, this.input = ConfigInput.text});
}

class WidgetType {
  final WidgetKind kind;
  final String label;
  final String description;
  final IconData icon;

  // Devices it can be added to
  final Set<DeviceRole> roles;

  // Settings a new widget starts with
  final Map<String, Object> defaults;

  // Settings the user can change, none means it is added without asking
  final List<ConfigField> fields;

  // Error text if the settings don't fit together, null if they do
  final String? Function(WidgetConfig config)? validate;

  final Widget Function(DeviceSession session, WidgetConfig config) build;

  const WidgetType({
    required this.kind,
    required this.label,
    required this.description,
    required this.icon,
    required this.roles,
    this.defaults = const {},
    this.fields = const [],
    this.validate,
    required this.build,
  });

  // Shown above the widget on the device page
  String title(WidgetConfig config) => config.label.isEmpty ? label : config.label;
}

const _label = ConfigField('label', 'NAME', hint: 'Shown above the widget');
const _sensorField = ConfigField(
  'field',
  'FIELD',
  hint: 'e.g. temperature - empty takes the first number',
  input: ConfigInput.field,
);
const _payloadField = ConfigField(
  'field',
  'FIELD',
  hint: 'e.g. brightness - empty sends the plain value',
  input: ConfigInput.field,
);
const _unit = ConfigField('unit', 'UNIT', hint: 'e.g. °C');
const _decimals = ConfigField('decimals', 'DECIMALS', input: ConfigInput.number);
const _min = ConfigField('min', 'MIN', input: ConfigInput.number);
const _max = ConfigField('max', 'MAX', input: ConfigInput.number);

String? _minBelowMax(WidgetConfig config) =>
    config.min < config.max ? null : 'Min must be below max';

const _sensor = {DeviceRole.sensor};
const _actuator = {DeviceRole.actuator};

final List<WidgetType> widgetTypes = [
  // Sensors
  WidgetType(
    kind: WidgetKind.value,
    label: 'Value',
    description: 'Current reading',
    icon: Icons.numbers,
    roles: _sensor,
    defaults: {'label': 'Value', 'field': '', 'unit': '', 'decimals': 1},
    fields: const [_label, _sensorField, _unit, _decimals],
    build: (session, config) => ValueDisplay(session: session, config: config),
  ),
  WidgetType(
    kind: WidgetKind.chart,
    label: 'Graph',
    description: 'Values over time',
    icon: Icons.show_chart,
    roles: _sensor,
    defaults: {'label': 'History', 'field': '', 'unit': '', 'decimals': 1},
    fields: const [_label, _sensorField, _unit, _decimals],
    build: (session, config) => SensorChart(session: session, config: config),
  ),
  WidgetType(
    kind: WidgetKind.gauge,
    label: 'Gauge',
    description: 'Value between min and max',
    icon: Icons.speed,
    roles: _sensor,
    defaults: {'label': 'Gauge', 'field': '', 'unit': '', 'decimals': 0, 'min': 0, 'max': 100},
    fields: const [_label, _sensorField, _unit, _decimals, _min, _max],
    validate: _minBelowMax,
    build: (session, config) => SensorGauge(session: session, config: config),
  ),
  WidgetType(
    kind: WidgetKind.pollRate,
    label: 'Polling rate',
    description: 'How often it is read',
    icon: Icons.timer_outlined,
    roles: _sensor,
    build: (session, config) => PollRateControl(session: session),
  ),

  // Actuators
  WidgetType(
    kind: WidgetKind.toggle,
    label: 'Switch',
    description: 'Turns a field on or off',
    icon: Icons.toggle_on_outlined,
    roles: _actuator,
    defaults: {'label': 'Power', 'field': 'on'},
    fields: const [_label, _payloadField],
    build: (session, config) => ToggleControl(session: session, config: config),
  ),
  WidgetType(
    kind: WidgetKind.slider,
    label: 'Slider',
    description: 'Sets a number',
    icon: Icons.linear_scale,
    roles: _actuator,
    defaults: {'label': 'Level', 'field': 'value', 'min': 0, 'max': 100, 'step': 1, 'unit': ''},
    fields: const [
      _label,
      _payloadField,
      _min,
      _max,
      ConfigField('step', 'STEP', hint: '0 for no steps', input: ConfigInput.number),
      _unit,
    ],
    validate: (config) =>
        _minBelowMax(config) ??
        (config.number('step', 1) < 0 ? 'Step must not be negative' : null),
    build: (session, config) => SliderControl(session: session, config: config),
  ),
  WidgetType(
    kind: WidgetKind.color,
    label: 'Colour',
    description: 'Picks a colour',
    icon: Icons.palette_outlined,
    roles: _actuator,
    defaults: {'label': 'Colour', 'field': 'color'},
    fields: const [_label, _payloadField],
    build: (session, config) => ColorControl(session: session, config: config),
  ),
  WidgetType(
    kind: WidgetKind.button,
    label: 'Button',
    description: 'Sends the request',
    icon: Icons.touch_app_outlined,
    roles: _actuator,
    defaults: {'label': 'Send', 'payload': ''},
    fields: const [
      _label,
      ConfigField('payload', 'PAYLOAD', hint: 'empty sends the stored payload'),
    ],
    build: (session, config) => SendButton(session: session, config: config),
  ),

  // Both
  WidgetType(
    kind: WidgetKind.response,
    label: 'Last response',
    description: 'Request and answer',
    icon: Icons.receipt_long_outlined,
    roles: const {DeviceRole.sensor, DeviceRole.actuator},
    build: (session, config) => ResponseView(session: session),
  ),
];

WidgetType widgetType(WidgetKind kind) => widgetTypes.firstWhere((t) => t.kind == kind);

import 'package:flutter/material.dart';

import 'database.dart';

// Entries of the "Add a device" list. Every device is a sensor or an
// actuator; a preset only fills in the form and adds some widgets to start
// with, the page can be changed freely afterwards

extension DeviceRoleLabel on DeviceRole {
  String get label => switch (this) {
        DeviceRole.sensor => 'sensor',
        DeviceRole.actuator => 'actuator',
      };

  IconData get icon => switch (this) {
        DeviceRole.sensor => Icons.sensors,
        DeviceRole.actuator => Icons.tune,
      };

  // Method a new device of this role starts with
  String get defaultMethod => switch (this) {
        DeviceRole.sensor => 'GET',
        DeviceRole.actuator => 'PUT',
      };
}

class DeviceTemplate {
  final DeviceRole role;
  final String group;
  final String label;
  final String subtitle;
  final IconData icon;

  // Payload a new device starts with
  final String payload;

  // Widgets the device page starts with, as kind and settings
  final List<(WidgetKind, Map<String, Object>)> widgets;

  const DeviceTemplate({
    required this.role,
    required this.group,
    required this.label,
    required this.subtitle,
    required this.icon,
    this.payload = '',
    this.widgets = const [],
  });
}

// Shown grouped in this order
const List<DeviceTemplate> deviceTemplates = [
  DeviceTemplate(
    role: DeviceRole.sensor,
    group: 'Start empty',
    label: 'Sensor',
    subtitle: 'is read in an interval',
    icon: Icons.sensors,
  ),
  DeviceTemplate(
    role: DeviceRole.actuator,
    group: 'Start empty',
    label: 'Actuator',
    subtitle: 'receives commands',
    icon: Icons.tune,
    payload: '{}',
  ),
  DeviceTemplate(
    role: DeviceRole.sensor,
    group: 'Presets',
    label: 'Temperature',
    subtitle: 'value, graph, interval',
    icon: Icons.thermostat,
    widgets: [
      (WidgetKind.value, {'label': 'Temperature', 'field': '', 'unit': '°C', 'decimals': 1}),
      (WidgetKind.chart, {'label': 'History', 'field': '', 'unit': '°C', 'decimals': 1}),
      (WidgetKind.pollRate, {}),
    ],
  ),
  DeviceTemplate(
    role: DeviceRole.actuator,
    group: 'Presets',
    label: 'Smart lamp',
    subtitle: 'switch, dimmer, colour',
    icon: Icons.lightbulb_outline,
    payload: '{"on":true,"brightness":100,"color":"#FFFFFF"}',
    widgets: [
      (WidgetKind.toggle, {'label': 'Power', 'field': 'on'}),
      (
        WidgetKind.slider,
        {'label': 'Brightness', 'field': 'brightness', 'min': 0, 'max': 100, 'step': 1, 'unit': '%'},
      ),
      (WidgetKind.color, {'label': 'Colour', 'field': 'color'}),
    ],
  ),
];

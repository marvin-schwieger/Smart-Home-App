import 'dart:convert';

import '../device_data.dart';

// Settings of one widget on a device page, stored as JSON in its row. Which
// keys a widget uses is listed in its entry in catalog.dart
class WidgetConfig {
  final Map<String, Object?> values;

  const WidgetConfig(this.values);

  // Falls back to no settings if [json] is not a JSON object
  factory WidgetConfig.decode(String json) {
    final decoded = decodeBody(json);
    return WidgetConfig(decoded is Map<String, dynamic> ? decoded : const {});
  }

  String encode() => jsonEncode(values);

  String text(String key) => switch (values[key]) {
        null => '',
        final value => '$value',
      };

  double number(String key, double fallback) => toNumber(values[key]) ?? fallback;

  // Name above the widget, empty to use the name of the widget type
  String get label => text('label');

  // Where the value is in the response or payload, see device_data.dart
  String get field => text('field');

  String get unit => text('unit');

  int get decimals => number('decimals', 1).round().clamp(0, 6);

  double get min => number('min', 0);

  double get max => number('max', 100);
}

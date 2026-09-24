import 'dart:convert';

// Reading values out of a response or payload and changing one field of a
// payload. A field is a key, a dotted path into nested objects like
// "sensor.temperature" (list items by index, "values.0"), or empty for the
// whole body

// JSON value of [body], or the trimmed text if it isn't JSON
Object? decodeBody(String body) {
  final text = body.trim();
  try {
    return jsonDecode(text);
  } on FormatException {
    return text;
  }
}

// Value at [field] in [data], null if the path doesn't exist
Object? readField(Object? data, String field) {
  final path = field.trim();
  if (path.isEmpty) return data;

  Object? value = data;
  for (final key in path.split('.')) {
    if (value is Map) {
      value = value[key];
    } else if (value is List) {
      final index = int.tryParse(key);
      value = index != null && index >= 0 && index < value.length ? value[index] : null;
    } else {
      return null;
    }
  }
  return value;
}

// Number at [field]. An empty field on a JSON object takes its first number,
// so {"temperature": 21.5, "unit": "°C"} works without setting a field
double? readNumber(Object? data, String field) {
  var value = readField(data, field);
  if (field.trim().isEmpty && value is Map) {
    value = value.values.firstWhere((v) => v is num, orElse: () => null);
  }
  return toNumber(value);
}

double? toNumber(Object? value) => switch (value) {
      num() => value.toDouble(),
      bool() => value ? 1 : 0,
      String() => double.tryParse(value.trim()),
      _ => null,
    };

bool? toBool(Object? value) => switch (value) {
      bool() => value,
      num() => value != 0,
      String() => switch (value.trim().toLowerCase()) {
          'true' || 'on' || '1' => true,
          'false' || 'off' || '0' => false,
          _ => null,
        },
      _ => null,
    };

// Text for a value display: the number with unit, or a text/boolean as it
// came. Null if [field] holds nothing that can be shown
String? displayValue(Object? data, String field, {int decimals = 1, String unit = ''}) {
  final number = readNumber(data, field);
  if (number != null) return formatNumber(number, decimals: decimals, unit: unit);
  final value = readField(data, field);
  if (value is String) return value.isEmpty ? null : value;
  return value is bool ? '$value' : null;
}

// [payload] with [field] set to [value]. An empty field replaces the whole
// payload with the plain value ("80", "true", "#FFAA00"), otherwise the
// payload is kept a JSON object and missing objects on the path are created
String writeField(String payload, String field, Object value) {
  final path = field.trim();
  if (path.isEmpty) return '$value';

  final decoded = decodeBody(payload);
  final root = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  final keys = path.split('.');
  var map = root;
  for (final key in keys.take(keys.length - 1)) {
    final child = map[key];
    map = map[key] = child is Map<String, dynamic> ? child : <String, dynamic>{};
  }
  map[keys.last] = value;
  return jsonEncode(root);
}

// Paths of all values in a JSON object, offered as suggestions when a
// widget's field is set, e.g. ["temperature", "unit"]
List<String> fieldPaths(Object? data, [String prefix = '']) {
  if (data is! Map) return const [];
  return [
    for (final MapEntry(:key, :value) in data.entries)
      if (value is Map) ...fieldPaths(value, '$prefix$key.') else '$prefix$key',
  ];
}

// e.g. 21.5 °C, the unit is left out if empty
String formatNumber(double value, {int decimals = 1, String unit = ''}) {
  final text = value.toStringAsFixed(decimals.clamp(0, 6));
  return unit.isEmpty ? text : '$text $unit';
}

// e.g. 5 s, 1 min, 90 s
String formatSeconds(int seconds) =>
    seconds >= 60 && seconds % 60 == 0 ? '${seconds ~/ 60} min' : '$seconds s';

// e.g. 14:05:09
String clockTime(DateTime time) =>
    [time.hour, time.minute, time.second].map((v) => '$v'.padLeft(2, '0')).join(':');

import 'dart:convert';

import 'package:database_test/device_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodeBody keeps text that is not JSON', () {
    expect(decodeBody(' 21.5 '), 21.5);
    expect(decodeBody('{"a": 1}'), {'a': 1});
    expect(decodeBody('hello'), 'hello');
  });

  test('readNumber takes the first number for an empty field', () {
    final data = decodeBody('{"temperature": 21.5, "unit": "°C"}');
    expect(readNumber(data, ''), 21.5);
    expect(readNumber(data, 'temperature'), 21.5);
    expect(readNumber(data, 'unit'), isNull);
    expect(readNumber(decodeBody('23'), ''), 23);
    expect(readNumber(decodeBody('"24.5"'), ''), 24.5);
  });

  test('readField follows nested objects and list indexes', () {
    final data = decodeBody('{"sensor": {"values": [1, 2, 3]}, "on": true}');
    expect(readField(data, 'sensor.values.1'), 2);
    expect(readField(data, 'sensor.values.9'), isNull);
    expect(readField(data, 'missing.path'), isNull);
    expect(toBool(readField(data, 'on')), isTrue);
    expect(toBool('off'), isFalse);
  });

  test('displayValue shows numbers with unit and texts as they are', () {
    final data = decodeBody('{"temp": 21.456, "state": "open"}');
    expect(displayValue(data, 'temp', decimals: 1, unit: '°C'), '21.5 °C');
    expect(displayValue(data, 'state'), 'open');
    expect(displayValue(data, 'nothing'), isNull);
    // e.g. an empty response
    expect(displayValue(decodeBody(''), ''), isNull);
  });

  test('writeField changes one field and keeps the others', () {
    expect(
      jsonDecode(writeField('{"on":true,"color":"#FFFFFF"}', 'brightness', 80)),
      {'on': true, 'color': '#FFFFFF', 'brightness': 80},
    );
    expect(jsonDecode(writeField('', 'light.on', false)), {
      'light': {'on': false},
    });
    // Not a JSON object: starts a new one
    expect(jsonDecode(writeField('garbage', 'on', true)), {'on': true});
    // Empty field: the plain value is the payload
    expect(writeField('{"on":true}', '', 42), '42');
    expect(writeField('', '', '#FFAA00'), '#FFAA00');
  });

  test('fieldPaths lists nested fields as dotted paths', () {
    expect(
      fieldPaths(decodeBody('{"temperature": 1, "meta": {"unit": "°C", "id": 3}}')),
      ['temperature', 'meta.unit', 'meta.id'],
    );
    expect(fieldPaths('plain text'), isEmpty);
  });
}

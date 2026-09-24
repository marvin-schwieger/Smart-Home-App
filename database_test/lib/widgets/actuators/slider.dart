import 'package:flutter/material.dart';

import '../../device_data.dart';
import '../../device_session.dart';
import '../../ui.dart';
import '../widget_config.dart';

// Slider for a number field of the payload between min and max, e.g. the
// brightness of a lamp or the setpoint of a thermostat
class SliderControl extends StatefulWidget {
  final DeviceSession session;
  final WidgetConfig config;

  const SliderControl({super.key, required this.session, required this.config});

  @override
  State<SliderControl> createState() => _SliderControlState();
}

class _SliderControlState extends State<SliderControl> {
  // Only set while dragging, the request is sent on release
  double? _dragValue;

  double get _step => widget.config.number('step', 1);

  // Decimals the step needs, e.g. 0 for 1, 1 for 0.5, 2 for 0.25
  int get _decimals {
    for (var decimals = 0; decimals < 4; decimals++) {
      final scaled = _step * _pow10(decimals);
      if ((scaled - scaled.round()).abs() < 1e-9) return decimals;
    }
    return 4;
  }

  static double _pow10(int n) => [1.0, 10.0, 100.0, 1000.0][n];

  // Whole numbers are sent as 80 instead of 80.0
  Object _rounded(double value) {
    final decimals = _decimals;
    return decimals == 0
        ? value.round()
        : double.parse(value.toStringAsFixed(decimals));
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final low = config.min;
    final high = config.max > low ? config.max : low + 1;
    final stored = toNumber(widget.session.payloadValue(config.field)) ?? low;
    final value = (_dragValue ?? stored).clamp(low, high);
    final steps = _step > 0 ? ((high - low) / _step).round() : 0;

    String format(double v) => formatNumber(v, decimals: _decimals, unit: config.unit);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          format(value),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        Slider(
          value: value,
          min: low,
          max: high,
          // Free movement if the step is 0 or would give too many notches
          divisions: steps >= 1 && steps <= 1000 ? steps : null,
          onChanged: (v) => setState(() => _dragValue = v),
          onChangeEnd: (v) {
            // write() updates the payload before it returns to the event loop,
            // so the slider doesn't jump back when the drag value is cleared
            widget.session.write(config.field, _rounded(v));
            setState(() => _dragValue = null);
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(format(low), style: const TextStyle(fontSize: 12, color: subtitleColor)),
            Text(format(high), style: const TextStyle(fontSize: 12, color: subtitleColor)),
          ],
        ),
      ],
    );
  }
}

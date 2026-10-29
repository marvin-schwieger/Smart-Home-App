import 'dart:math';

import 'package:flutter/material.dart';

import '../../device_data.dart';
import '../../device_session.dart';
import '../../ui.dart';
import '../widget_config.dart';

// Half circle that fills from min to max with the current value of a sensor,
// e.g. humidity between 0 and 100 %
class SensorGauge extends StatelessWidget {
  final DeviceSession session;
  final WidgetConfig config;

  const SensorGauge({super.key, required this.session, required this.config});

  @override
  Widget build(BuildContext context) {
    final latest = session.latest;
    final value = latest == null ? null : readNumber(latest.data, config.field);
    final low = config.min;
    final high = config.max;
    final fraction = value == null || high <= low
        ? 0.0
        : ((value - low) / (high - low)).clamp(0.0, 1.0);

    String format(double v) =>
        formatNumber(v, decimals: config.decimals, unit: config.unit);

    return Column(
      children: [
        SizedBox(
          height: 130,
          width: double.infinity,
          child: CustomPaint(
            painter: _GaugePainter(
              fraction: fraction,
              color: session.lastFailed
                  ? context.design.error
                  : Theme.of(context).colorScheme.primary,
              track: context.design.field,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Text(
                value == null ? '--' : format(value),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(format(low), style: TextStyle(fontSize: 12, color: context.design.muted)),
            Text(format(high), style: TextStyle(fontSize: 12, color: context.design.muted)),
          ],
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  static const double stroke = 14;

  // 0 = min, 1 = max
  final double fraction;
  final Color color;

  // The part of the arc above the value
  final Color track;

  _GaugePainter({required this.fraction, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    // Centre on the bottom edge, so the half circle stands on it
    final radius = min(size.width / 2, size.height) - stroke / 2;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height - stroke / 2),
      radius: radius,
    );
    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // From the left through the top to the right
    canvas.drawArc(rect, pi, pi, false, arc(track));
    if (fraction > 0) canvas.drawArc(rect, pi, pi * fraction, false, arc(color));
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.track != track;
}

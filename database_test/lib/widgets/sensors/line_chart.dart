import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../device_data.dart';
import '../../device_session.dart';
import '../../ui.dart';
import '../widget_config.dart';

// Line chart of the samples of a sensor; x is the time in seconds, y the
// value of the configured field. Samples without that value are left out
class SensorChart extends StatelessWidget {
  final DeviceSession session;
  final WidgetConfig config;

  const SensorChart({super.key, required this.session, required this.config});

  @override
  Widget build(BuildContext context) {
    double x(DateTime time) => time.millisecondsSinceEpoch / 1000;
    DateTime time(double x) => DateTime.fromMillisecondsSinceEpoch((x * 1000).round());

    final spots = [
      for (final sample in session.samples)
        if (readNumber(sample.data, config.field) case final value?)
          FlSpot(x(sample.time), value),
    ];

    if (spots.length < 2) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'The graph starts after two readings',
            style: TextStyle(color: subtitleColor),
          ),
        ),
      );
    }

    final color = Theme.of(context).colorScheme.primary;
    final values = spots.map((s) => s.y);
    final lowest = values.reduce(min);
    final highest = values.reduce(max);
    // Headroom so the line never touches the edges, also when all values
    // are the same
    final span = highest - lowest;
    final padding = span == 0 ? max(highest.abs() * 0.1, 1) : span * 0.15;
    final minX = spots.first.x;
    final maxX = spots.last.x;

    return SizedBox(
      height: 220,
      child: LineChart(
        duration: Duration.zero, // no animation, new points come in constantly
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: lowest - padding,
          maxY: highest + padding,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
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
                  child: Text(meta.formattedValue, style: const TextStyle(fontSize: 11)),
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
                  child: Text(clockTime(time(value)), style: const TextStyle(fontSize: 11)),
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
                    '${formatNumber(spot.y, decimals: config.decimals, unit: config.unit)}'
                    '\n${clockTime(time(spot.x))}',
                    const TextStyle(color: Colors.white, fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

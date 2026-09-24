import 'package:flutter/material.dart';

import '../../device_data.dart';
import '../../device_session.dart';
import '../../ui.dart';
import '../widget_config.dart';

// Current value of a sensor in big, e.g. 21.4 °C, and when it was read
class ValueDisplay extends StatelessWidget {
  final DeviceSession session;
  final WidgetConfig config;

  const ValueDisplay({super.key, required this.session, required this.config});

  @override
  Widget build(BuildContext context) {
    final latest = session.latest;
    final value = latest == null
        ? null
        : displayValue(
            latest.data,
            config.field,
            decimals: config.decimals,
            unit: config.unit,
          );

    final String status;
    if (latest == null) {
      status = session.lastFailed
          ? session.lastResponse ?? ''
          : 'waiting for the first reading';
    } else if (value == null) {
      status = config.field.isEmpty
          ? 'no number in the response'
          : 'no "${config.field}" in the response';
    } else {
      status = 'at ${clockTime(latest.time)} · every ${formatSeconds(session.pollSeconds)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value ?? '--',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            // Red while the sensor can't be read, the last value stays visible
            color: session.lastFailed ? errorColor : Colors.black87,
          ),
        ),
        Text(
          status,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: session.lastFailed || value == null && latest != null
                ? errorColor
                : subtitleColor,
          ),
        ),
      ],
    );
  }
}

// Current value for the room list, rebuilt with every new reading
class SensorBadge extends StatelessWidget {
  final DeviceSession session;

  // Field and unit of the first value, gauge or graph widget of the sensor
  final WidgetConfig config;

  const SensorBadge({super.key, required this.session, required this.config});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final latest = session.latest;
        final value = latest == null
            ? null
            : displayValue(
                latest.data,
                config.field,
                decimals: config.decimals,
                unit: config.unit,
              );
        // A sensor that answers with plain text must not push the card apart
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 110),
          child: Text(
            value ?? '--',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: session.lastFailed ? errorColor : Colors.black87,
            ),
          ),
        );
      },
    );
  }
}

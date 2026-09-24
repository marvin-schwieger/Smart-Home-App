import 'package:flutter/material.dart';

import '../../device_data.dart';
import '../../device_session.dart';
import '../widget_config.dart';

// Switch for a true/false field of the payload, e.g. "on" of a lamp
class ToggleControl extends StatelessWidget {
  final DeviceSession session;
  final WidgetConfig config;

  const ToggleControl({super.key, required this.session, required this.config});

  @override
  Widget build(BuildContext context) {
    final on = toBool(session.payloadValue(config.field)) ?? false;

    return Row(
      children: [
        Expanded(
          child: Text(
            on ? 'On' : 'Off',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
        Switch(
          value: on,
          onChanged: (value) => session.write(config.field, value),
        ),
      ],
    );
  }
}

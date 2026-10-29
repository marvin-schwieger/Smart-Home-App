import 'package:flutter/material.dart';

import '../../device_session.dart';
import '../../request.dart';
import '../../ui.dart';
import '../widget_config.dart';

// Sends the request of the device once, with a fixed payload if one is set
// (e.g. {"action": "reset"}), otherwise with the stored payload. The stored
// payload is not changed by it
class SendButton extends StatelessWidget {
  final DeviceSession session;
  final WidgetConfig config;

  const SendButton({super.key, required this.session, required this.config});

  @override
  Widget build(BuildContext context) {
    final payload = config.text('payload');
    final method = session.device.method;
    final design = context.design;

    return SizedBox(
      width: double.infinity,
      height: design.choiceHeight + 4,
      child: FilledButton.icon(
        onPressed: () => session.send(payload: payload.isEmpty ? null : payload),
        icon: const Icon(Icons.send, size: 18),
        label: Text(
          payload.isNotEmpty && methodHasPayload(method) ? '$method  $payload' : method,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(design.fieldRadius)),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../device_session.dart';
import '../request.dart';
import '../ui.dart';

// The request the device sends (method, URI and payload if it has one) and
// the result of the last request
class ResponseView extends StatelessWidget {
  final DeviceSession session;

  const ResponseView({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final device = session.device;
    final response = session.lastResponse;
    final design = context.design;
    final details = [
      if (session.lastCode case final code?) 'Code $code',
      if (session.lastElapsed case final elapsed?) '${elapsed.inMilliseconds} ms',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: design.highlight,
                borderRadius: BorderRadius.circular(design.badgeRadius),
              ),
              child: Text(
                device.method,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                buildUri(device.scheme, device.host, device.path).toString(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ],
        ),
        if (methodHasPayload(device.method) && device.payload.isNotEmpty) ...[
          const SizedBox(height: 10),
          CodeBox(device.payload),
        ],
        const SizedBox(height: 10),
        if (response == null)
          Text(
            session.isSensor
                ? 'Waiting for the first response...'
                : 'Nothing sent yet - use a control above',
            style: TextStyle(fontSize: 13, color: design.muted),
          )
        else ...[
          CodeBox(response),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              details,
              style: TextStyle(
                fontSize: 12,
                color: session.lastFailed ? design.error : design.muted,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

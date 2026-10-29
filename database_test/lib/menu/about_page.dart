import 'package:flutter/material.dart';

import '../ui.dart';

const String appName = 'Your home';

// Keep in line with the version in pubspec.yaml
const String appVersion = '0.1.0';

// What the app is and what it is built with, opened from the menu
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: EdgeInsets.all(design.padding),
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: design.highlight,
                borderRadius: BorderRadius.circular(design.cardRadius),
              ),
              child: Icon(Icons.home_outlined, size: 40, color: scheme.primary),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(appName, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ),
          Center(child: Text('Version $appVersion', style: TextStyle(color: design.muted))),
          SizedBox(height: design.spacing + 8),
          const SectionCard(
            title: 'What it does',
            children: [
              Text(
                'Reads and controls IoT devices over CoAP and HTTP. Sensors are '
                'polled in an interval, actuators get their commands from '
                'switches, sliders and colour pickers. Built as test app for a '
                'bachelor thesis.',
                style: TextStyle(height: 1.4),
              ),
            ],
          ),
          const SectionCard(
            title: 'Security',
            children: [
              InfoRow('CoAP', 'DTLS with a pre-shared key, OSCORE with AES-CCM, AES-GCM or '
                  'ChaCha20-Poly1305'),
              InfoRow('HTTP', 'Basic and OAuth 2.0 (client credentials), over TLS with the '
                  'own CA of a device'),
              InfoRow('Accounts', 'Only on this device, passwords kept as PBKDF2-HMAC-SHA-256 '
                  'hash'),
            ],
          ),
          const SectionCard(
            title: 'Built with',
            children: [
              Text(
                'Flutter, drift (SQLite), coap, http, pointycastle, fl_chart, '
                'flex_color_picker and reorderable_grid_view.',
                style: TextStyle(height: 1.4),
              ),
            ],
          ),
          WideOutlinedButton(
            icon: Icons.description_outlined,
            label: 'Open source licenses',
            onPressed: () => showLicensePage(
              context: context,
              applicationName: appName,
              applicationVersion: appVersion,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';

import '../../device_session.dart';
import '../../ui.dart';
import '../widget_config.dart';

// e.g. #FFAA00
String colorHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

// Reads #RRGGBB (the # is optional), null if [value] is no such colour
Color? parseColorHex(Object? value) {
  if (value is! String) return null;
  final hex = value.trim().replaceFirst('#', '');
  if (hex.length != 6) return null;
  final rgb = int.tryParse(hex, radix: 16);
  return rgb == null ? null : Color(0xFF000000 | rgb);
}

// Colour of a field of the payload as #RRGGBB, e.g. "color" of a lamp
class ColorControl extends StatelessWidget {
  final DeviceSession session;
  final WidgetConfig config;

  const ColorControl({super.key, required this.session, required this.config});

  // Colour popup from flex_color_picker: a wheel for any colour plus the
  // Material colours as presets. Cancel returns the start colour unchanged
  Future<void> _pickColor(BuildContext context, Color current) async {
    final color = await showColorPickerDialog(
      context,
      current,
      title: Text('Pick a colour', style: Theme.of(context).textTheme.titleLarge),
      pickersEnabled: const {
        ColorPickerType.wheel: true,
        ColorPickerType.primary: true,
        ColorPickerType.accent: false,
      },
      pickerTypeLabels: const {
        ColorPickerType.wheel: 'Wheel',
        ColorPickerType.primary: 'Presets',
      },
      wheelDiameter: 240,
      wheelWidth: 20,
      showColorCode: true, // hex field, also accepts a typed code
      colorCodeHasColor: true,
      // Same #RRGGBB format as in the payload instead of the Dart 0xAARRGGBB
      copyPasteBehavior: const ColorPickerCopyPasteBehavior(
        copyFormat: ColorPickerCopyFormat.numHexRRGGBB,
      ),
      actionButtons: const ColorPickerActionButtons(
        dialogOkButtonLabel: 'Apply',
        dialogOkButtonType: ColorPickerActionButtonType.filled,
      ),
      constraints: const BoxConstraints(minWidth: 320, maxWidth: 320),
    );
    if (color != current) await session.write(config.field, colorHex(color));
  }

  @override
  Widget build(BuildContext context) {
    final color = parseColorHex(session.payloadValue(config.field)) ?? Colors.white;

    return InkWell(
      onTap: () => _pickColor(context, color),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: fieldColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black12),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                colorHex(color),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
            Text(
              'Pick colour',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            const Icon(Icons.chevron_right, color: Colors.black45),
          ],
        ),
      ),
    );
  }
}

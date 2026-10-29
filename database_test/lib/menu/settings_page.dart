import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';

import '../design/app_design.dart';
import '../design/design_presets.dart';
import '../design/design_settings.dart';
import '../settings/app_settings.dart';
import '../ui.dart';

// Dark mode and design, opened from the menu. Every change shows right away
// in the whole app, the preview at the end shows the main components
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _themeModes = {
    'System': ThemeMode.system,
    'Light': ThemeMode.light,
    'Dark': ThemeMode.dark,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) {
        final settings = appSettings.design;
        final design = context.design;
        final brightness = Theme.of(context).brightness;

        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: EdgeInsets.all(design.padding),
            children: [
              SectionCard(
                title: 'Theme',
                children: [
                  ChoiceRow(
                    options: _themeModes.keys.toList(),
                    selected: _themeModes.entries
                        .firstWhere((e) => e.value == appSettings.themeMode)
                        .key,
                    onSelected: (label) => appSettings.setThemeMode(_themeModes[label]!),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'System follows the setting of the device',
                    style: TextStyle(fontSize: 12, color: design.muted),
                  ),
                ],
              ),
              SectionCard(
                title: 'Design',
                children: [
                  for (final preset in designPresets)
                    OptionTile(
                      leading: _PresetSwatch(
                        brightness == Brightness.dark ? preset.dark : preset.light,
                        accent: preset.accent,
                      ),
                      label: preset.name,
                      subtitle: preset.description,
                      selected: settings.preset == preset.id,
                      onTap: () => appSettings.setDesign(settings.withPreset(preset.id)),
                    ),
                ],
              ),
              SectionCard(
                title: 'Adjust ${settings.basis.name}',
                children: [
                  const FieldLabel('Accent colour'),
                  _AccentPicker(settings: settings),
                  SizedBox(height: design.spacing),
                  _SliderSetting(
                    label: 'Corner roundness',
                    value: settings.roundness,
                    range: DesignSettings.roundnessRange,
                    low: 'Square',
                    high: 'Round',
                    onChanged: (value, save) =>
                        appSettings.setDesign(settings.copyWith(roundness: value), save: save),
                  ),
                  _SliderSetting(
                    label: 'Size of the controls',
                    value: settings.size,
                    range: DesignSettings.sizeRange,
                    low: 'Compact',
                    high: 'Large',
                    onChanged: (value, save) =>
                        appSettings.setDesign(settings.copyWith(size: value), save: save),
                  ),
                  _SliderSetting(
                    label: 'Text size',
                    value: settings.textScale,
                    range: DesignSettings.textScaleRange,
                    low: 'Small',
                    high: 'Large',
                    onChanged: (value, save) =>
                        appSettings.setDesign(settings.copyWith(textScale: value), save: save),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Outlines'),
                    subtitle: Text(
                      'Thin borders around cards and fields',
                      style: TextStyle(fontSize: 12, color: design.muted),
                    ),
                    value: settings.hasBorders,
                    onChanged: (on) => appSettings.setDesign(settings.withBorders(on)),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      // Back to the preset as it is, the text size stays
                      onPressed: settings == settings.withPreset(settings.preset)
                          ? null
                          : () => appSettings.setDesign(settings.withPreset(settings.preset)),
                      icon: const Icon(Icons.restart_alt),
                      label: Text('Reset to ${settings.basis.name}'),
                    ),
                  ),
                ],
              ),
              const SectionCard(title: 'Preview', children: [_DesignPreview()]),
            ],
          ),
        );
      },
    );
  }
}

// Small picture of a preset: its background with a card and the accent
class _PresetSwatch extends StatelessWidget {
  final AppDesign design;
  final Color accent;

  const _PresetSwatch(this.design, {required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: design.background,
        borderRadius: BorderRadius.circular(design.badgeRadius),
        border: Border.all(color: design.outline),
      ),
      child: Container(
        width: 26,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: design.card,
          borderRadius: BorderRadius.circular(design.badgeRadius / 2),
          border: design.borderWidth > 0 ? Border.all(color: design.outline) : null,
        ),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

// Round color swatches: the accent of the preset, a few common ones and any
// color from the color wheel
class _AccentPicker extends StatelessWidget {
  final DesignSettings settings;

  const _AccentPicker({required this.settings});

  static const _accents = [
    Color(0xFF4F5DF5),
    Color(0xFF2563EB),
    Color(0xFF0891B2),
    Color(0xFF0F9D7A),
    Color(0xFF16A34A),
    Color(0xFFCA8A04),
    Color(0xFFEA580C),
    Color(0xFFDC2626),
    Color(0xFFDB2777),
    Color(0xFF7C3AED),
    Color(0xFF475569),
  ];

  Future<void> _pickCustom(BuildContext context) async {
    final color = await showColorPickerDialog(
      context,
      settings.accentColor,
      title: Text('Accent colour', style: Theme.of(context).textTheme.titleLarge),
      pickersEnabled: const {
        ColorPickerType.wheel: true,
        ColorPickerType.primary: false,
        ColorPickerType.accent: false,
      },
      wheelDiameter: 240,
      wheelWidth: 20,
      showColorCode: true,
      colorCodeHasColor: true,
      actionButtons: const ColorPickerActionButtons(
        dialogOkButtonLabel: 'Apply',
        dialogOkButtonType: ColorPickerActionButtonType.filled,
      ),
      constraints: const BoxConstraints(minWidth: 320, maxWidth: 320),
    );
    if (color != settings.accentColor) await appSettings.setDesign(settings.withAccent(color));
  }

  @override
  Widget build(BuildContext context) {
    final custom = settings.accent != null && !_accents.contains(settings.accent);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _Swatch(
          color: settings.basis.accent,
          selected: settings.accent == null,
          tooltip: 'As in ${settings.basis.name}',
          icon: Icons.auto_awesome,
          onTap: () => appSettings.setDesign(settings.withAccent(null)),
        ),
        for (final color in _accents)
          if (color != settings.basis.accent)
            _Swatch(
              color: color,
              selected: settings.accent == color,
              tooltip: '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase()}',
              onTap: () => appSettings.setDesign(settings.withAccent(color)),
            ),
        _Swatch(
          color: custom ? settings.accent! : context.design.field,
          selected: custom,
          tooltip: 'Any colour',
          icon: Icons.colorize,
          onTap: () => _pickCustom(context),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final String tooltip;
  final IconData? icon;
  final VoidCallback onTap;

  const _Swatch({
    required this.color,
    required this.selected,
    required this.tooltip,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final onColor = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.onSurface : context.design.outline,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: 18, color: onColor)
              : icon == null
                  ? null
                  : Icon(icon, size: 16, color: onColor),
        ),
      ),
    );
  }
}

// Slider with its name and value above and the ends below. [onChanged] gets
// save false while dragging and true once it is let go
class _SliderSetting extends StatelessWidget {
  final String label;
  final double value;
  final (double, double) range;
  final String low;
  final String high;
  final void Function(double value, bool save) onChanged;

  const _SliderSetting({
    required this.label,
    required this.value,
    required this.range,
    required this.low,
    required this.high,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: context.design.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text('${(value * 100).round()}%', style: muted),
          ],
        ),
        Slider(
          value: value.clamp(range.$1, range.$2),
          min: range.$1,
          max: range.$2,
          divisions: ((range.$2 - range.$1) / 0.05).round(),
          onChanged: (value) => onChanged(value, false),
          onChangeEnd: (value) => onChanged(value, true),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(low, style: muted), Text(high, style: muted)],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// The main components with the current design, to see a change at once
class _DesignPreview extends StatefulWidget {
  const _DesignPreview();

  @override
  State<_DesignPreview> createState() => _DesignPreviewState();
}

class _DesignPreviewState extends State<_DesignPreview> {
  String _method = 'PUT';

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    return Container(
      padding: EdgeInsets.all(design.padding * 0.75),
      decoration: BoxDecoration(
        color: design.background,
        borderRadius: BorderRadius.circular(design.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesignCard(
            onTap: () {},
            child: Row(
              children: [
                const IconBox(Icons.lightbulb_outline, accent: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Desk lamp', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('in Office · 3 widgets', style: TextStyle(fontSize: 12, color: design.muted)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: design.field,
                    borderRadius: BorderRadius.circular(design.badgeRadius),
                  ),
                  child: Text(_method, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          SizedBox(height: design.spacing),
          ChoiceRow(
            options: const ['GET', 'PUT', 'POST'],
            selected: _method,
            onSelected: (method) => setState(() => _method = method),
          ),
          SizedBox(height: design.spacing),
          TextField(decoration: fieldDecoration('NAME', hint: 'e.g. Desk lamp')),
          SizedBox(height: design.spacing),
          SaveButton(enabled: true, label: 'Save', onPressed: () {}),
        ],
      ),
    );
  }
}

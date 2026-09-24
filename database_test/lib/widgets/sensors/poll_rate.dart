import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../device_data.dart';
import '../../device_session.dart';
import '../../ui.dart';

// Changes how often the sensor is read, takes effect right away
class PollRateControl extends StatelessWidget {
  final DeviceSession session;

  const PollRateControl({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return PollIntervalPicker(
      seconds: session.pollSeconds,
      onChanged: session.setPollSeconds,
    );
  }
}

// Preset intervals plus "Custom", which asks for any number of seconds
class PollIntervalPicker extends StatelessWidget {
  static const List<int> presets = [1, 5, 30, 60];

  final int seconds;
  final ValueChanged<int> onChanged;

  const PollIntervalPicker({super.key, required this.seconds, required this.onChanged});

  Future<void> _askCustom(BuildContext context) async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _CustomIntervalDialog(initial: seconds),
    );
    if (value != null) onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final isCustom = !presets.contains(seconds);

    return Row(
      children: [
        for (final preset in presets) ...[
          Expanded(
            child: ChoiceButton(
              label: formatSeconds(preset),
              selected: preset == seconds,
              onTap: () => onChanged(preset),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          flex: 2,
          child: ChoiceButton(
            label: isCustom ? formatSeconds(seconds) : 'Custom',
            selected: isCustom,
            onTap: () => _askCustom(context),
          ),
        ),
      ],
    );
  }
}

class _CustomIntervalDialog extends StatefulWidget {
  final int initial;

  const _CustomIntervalDialog({required this.initial});

  @override
  State<_CustomIntervalDialog> createState() => _CustomIntervalDialogState();
}

class _CustomIntervalDialogState extends State<_CustomIntervalDialog> {
  late final _ctrl = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int? get _seconds {
    final value = int.tryParse(_ctrl.text);
    return value != null && value >= 1 ? value : null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom interval'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: 'Every', suffixText: 'seconds'),
        onChanged: (_) => setState(() {}), // keeps the Apply button in sync
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _seconds == null ? null : () => Navigator.pop(context, _seconds),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

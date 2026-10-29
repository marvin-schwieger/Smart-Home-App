import 'package:flutter/material.dart';

import '../ui.dart';
import 'device_auth.dart';

// Opens the authentication page of a device on [scheme]. Returns the edited
// authentication, null if the user went back without applying it
Future<DeviceAuth?> showAuthPage(
  BuildContext context, {
  required String scheme,
  required DeviceAuth auth,
  required String deviceName,
}) =>
    Navigator.push<DeviceAuth>(
      context,
      MaterialPageRoute(
        builder: (_) => AuthPage(scheme: scheme, auth: auth, deviceName: deviceName),
      ),
    );

IconData authIcon(AuthMethod method) => switch (method) {
      AuthMethod.none => Icons.lock_open_outlined,
      AuthMethod.dtlsPsk => Icons.vpn_key_outlined,
      AuthMethod.oscore => Icons.enhanced_encryption_outlined,
      AuthMethod.basic => Icons.password,
      AuthMethod.oauth2 => Icons.token_outlined,
    };

// Page of its own for the authentication, so the device sheet stays short:
// first the methods that fit the scheme, then the settings of the picked
// one. Nothing is stored here, the device sheet saves it with the device
class AuthPage extends StatefulWidget {
  final String scheme;
  final DeviceAuth auth;
  final String deviceName;

  const AuthPage({
    super.key,
    required this.scheme,
    required this.auth,
    required this.deviceName,
  });

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  late DeviceAuth _auth = widget.auth.forScheme(widget.scheme);

  // Per setting key, kept while switching methods so typed values stay
  final Map<String, TextEditingController> _controllers = {};

  // Secret fields the user made visible with the eye button
  final Set<String> _revealed = {};

  TextEditingController _controller(String key) =>
      _controllers.putIfAbsent(key, () => TextEditingController(text: _auth[key]));

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = authType(_auth.method);
    final error = _auth.validate(widget.scheme);
    final name = widget.deviceName.trim();
    final design = context.design;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Authentication'),
            Text(
              '${name.isEmpty ? 'New device' : name} · ${widget.scheme}://',
              style: TextStyle(fontSize: 12, color: design.muted),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: EdgeInsets.all(design.padding),
        children: [
          SectionCard(
            title: 'Method',
            children: [
              for (final option in authTypesFor(widget.scheme))
                OptionTile(
                  leading: IconBox(authIcon(option.method), selected: option.method == _auth.method),
                  label: option.label,
                  subtitle: option.subtitle,
                  selected: option.method == _auth.method,
                  onTap: () => setState(() => _auth = _auth.withMethod(option.method)),
                ),
            ],
          ),
          if (type.fields.isNotEmpty)
            SectionCard(
              title: '${type.label} settings',
              children: [
                Text(type.description, style: TextStyle(fontSize: 12, color: design.muted)),
                for (final field in type.fields) ...[
                  const SizedBox(height: 12),
                  field.input == AuthInput.choice ? _choiceField(field) : _textField(field),
                ],
              ],
            ),
          if (widget.scheme == 'https')
            SectionCard(
              title: 'Certificate of the device',
              children: [_textField(caCertField)],
            ),
          SaveButton(
            enabled: error == null,
            label: error ?? 'Apply',
            onPressed: () => Navigator.pop(context, _auth),
          ),
        ],
      ),
    );
  }

  Widget _choiceField(AuthField field) {
    return InputDecorator(
      decoration: fieldDecoration(field.label, helper: field.helper),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _auth.choice(field),
          isDense: true,
          isExpanded: true,
          items: [
            for (final option in field.options) DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: (option) {
            if (option != null) setState(() => _auth = _auth.withValue(field.key, option));
          },
        ),
      ),
    );
  }

  Widget _textField(AuthField field) {
    final isPem = field.input == AuthInput.pem;
    final hidden = field.secret && !_revealed.contains(field.key);
    return TextField(
      controller: _controller(field.key),
      obscureText: hidden,
      autocorrect: false,
      enableSuggestions: false,
      minLines: isPem ? 3 : 1,
      maxLines: isPem ? 6 : 1,
      style: field.input == AuthInput.text
          ? null
          : const TextStyle(fontFamily: 'monospace', fontSize: 13),
      decoration: fieldDecoration(field.label, hint: field.hint, helper: field.helper).copyWith(
        suffixIcon: field.secret
            ? IconButton(
                onPressed: () => setState(() {
                  if (!_revealed.remove(field.key)) _revealed.add(field.key);
                }),
                icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                tooltip: hidden ? 'Show' : 'Hide',
              )
            : null,
      ),
      onChanged: (value) => setState(() => _auth = _auth.withValue(field.key, value)),
    );
  }
}

import 'package:flutter/material.dart';

import '../ui.dart';
import 'accounts.dart';
import 'sign_in_page.dart';

// Creating an account, which signs it in right away
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _repeatCtrl = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _repeatCtrl.dispose();
    super.dispose();
  }

  // What is missing, shown on the button like in the device sheet
  String? get _missing => validateRegistration(
        name: _nameCtrl.text,
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        repeated: _repeatCtrl.text,
      );

  Future<void> _register() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.register(
        name: _nameCtrl.text,
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );
      if (mounted) Navigator.pop(context);
    } on AccountException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    final missing = _missing;

    Widget field(TextEditingController controller, String label, {String? helper, bool password = false}) =>
        Padding(
          padding: EdgeInsets.only(bottom: design.spacing),
          child: TextField(
            controller: controller,
            obscureText: password && !_showPassword,
            autocorrect: !password,
            keyboardType: label == 'EMAIL' ? TextInputType.emailAddress : null,
            decoration: fieldDecoration(label, helper: helper).copyWith(
              suffixIcon: password
                  ? IconButton(
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                      icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      tooltip: _showPassword ? 'Hide' : 'Show',
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: ListView(
        padding: EdgeInsets.all(design.padding + 4),
        children: [
          const Text('New account', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Stored only on this device. The password is kept as a salted hash, '
            'never in plain text.',
            style: TextStyle(color: design.muted),
          ),
          SizedBox(height: design.spacing + 8),
          field(_nameCtrl, 'NAME'),
          field(_emailCtrl, 'EMAIL'),
          field(
            _passwordCtrl,
            'PASSWORD',
            helper: 'At least $minPasswordLength characters',
            password: true,
          ),
          field(_repeatCtrl, 'REPEAT PASSWORD', password: true),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: design.error)),
            const SizedBox(height: 12),
          ],
          SaveButton(
            enabled: missing == null && !_busy,
            label: _busy ? 'Creating account...' : missing ?? 'Create account',
            onPressed: _register,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const SignInPage()),
              ),
              child: const Text('Already have an account? Sign in'),
            ),
          ),
        ],
      ),
    );
  }
}

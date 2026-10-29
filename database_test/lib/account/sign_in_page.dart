import 'package:flutter/material.dart';

import '../ui.dart';
import 'accounts.dart';
import 'register_page.dart';

// Signing in with email and password, opened from the menu
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _showPassword = false;

  // While the password is checked, which takes a moment on purpose
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool get _filled => _emailCtrl.text.trim().isNotEmpty && _passwordCtrl.text.isNotEmpty;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.signIn(_emailCtrl.text, _passwordCtrl.text);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: ListView(
        padding: EdgeInsets.all(design.padding + 4),
        children: [
          const Text('Welcome back', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Accounts live only on this device, nothing is sent anywhere.',
            style: TextStyle(color: design.muted),
          ),
          SizedBox(height: design.spacing + 8),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: fieldDecoration('EMAIL'),
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(height: design.spacing),
          TextField(
            controller: _passwordCtrl,
            obscureText: !_showPassword,
            autofillHints: const [AutofillHints.password],
            decoration: fieldDecoration('PASSWORD').copyWith(
              suffixIcon: IconButton(
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                tooltip: _showPassword ? 'Hide' : 'Show',
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _filled && !_busy ? _signIn() : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: design.error)),
          ],
          SizedBox(height: design.spacing + 8),
          SaveButton(
            enabled: _filled && !_busy,
            label: _busy ? 'Signing in...' : 'Sign in',
            onPressed: _signIn,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const RegisterPage()),
              ),
              child: const Text('No account yet? Create one'),
            ),
          ),
        ],
      ),
    );
  }
}

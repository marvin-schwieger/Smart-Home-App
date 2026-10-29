import 'package:flutter/material.dart';

import '../database.dart';
import '../ui.dart';
import 'accounts.dart';

// The signed in account: its details, signing out and deleting it
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  Future<void> _signOut(BuildContext context) async {
    await session.signOut();
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _delete(BuildContext context) async {
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteDialog(),
    );
    if (deleted == true && context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final account = session.account;
        final design = context.design;
        if (account == null) return const Scaffold();

        final created = account.createdAt;
        return Scaffold(
          appBar: AppBar(title: const Text('Account')),
          body: ListView(
            padding: EdgeInsets.all(design.padding),
            children: [
              Center(child: AccountAvatar(account: account, radius: 40)),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  account.name,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              Center(child: Text(account.email, style: TextStyle(color: design.muted))),
              SizedBox(height: design.spacing + 8),
              SectionCard(
                title: 'Details',
                children: [
                  InfoRow('Name', account.name),
                  InfoRow('Email', account.email),
                  InfoRow('Created', '${created.day}.${created.month}.${created.year}'),
                  InfoRow(
                    'Password',
                    'PBKDF2-HMAC-SHA-256 with ${account.iterations} iterations and a '
                        'random salt',
                  ),
                  InfoRow('Stored', 'Only on this device'),
                ],
              ),
              SaveButton(enabled: true, label: 'Sign out', onPressed: () => _signOut(context)),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => _delete(context),
                  style: TextButton.styleFrom(foregroundColor: design.error),
                  child: const Text('Delete account'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Asks for the password before the account is deleted. Pops true once it is
class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog();

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _passwordCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.deleteAccount(_passwordCtrl.text);
      if (mounted) Navigator.pop(context, true);
    } on AccountException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Rooms and devices stay, only the account is removed.'),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            autofocus: true,
            decoration: fieldDecoration('PASSWORD'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: context.design.error)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _delete,
          style: FilledButton.styleFrom(backgroundColor: context.design.error),
          child: Text(_busy ? 'Deleting...' : 'Delete'),
        ),
      ],
    );
  }
}

// Circle with the initials of the account, a person icon without one
class AccountAvatar extends StatelessWidget {
  final Account? account;
  final double radius;

  const AccountAvatar({super.key, required this.account, required this.radius});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final account = this.account;
    return CircleAvatar(
      radius: radius,
      backgroundColor: account == null ? context.design.field : scheme.primary,
      foregroundColor: account == null ? context.design.icon : scheme.onPrimary,
      child: account == null
          ? Icon(Icons.person_outline, size: radius)
          : Text(
              account.initials,
              style: TextStyle(fontSize: radius * 0.7, fontWeight: FontWeight.bold),
            ),
    );
  }
}

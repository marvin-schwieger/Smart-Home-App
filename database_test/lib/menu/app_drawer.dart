import 'package:flutter/material.dart';

import '../account/account_page.dart';
import '../account/accounts.dart';
import '../account/sign_in_page.dart';
import '../database.dart';
import '../settings/app_settings.dart';
import '../ui.dart';
import 'about_page.dart';
import 'settings_page.dart';

// Menu of the home page, opened with the hamburger button: the account,
// the settings, about and a switch for the dark mode
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  // Closes the menu first, so going back from [page] lands on the home page
  void _open(BuildContext context, Widget page) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _signOut(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    await session.signOut();
    messenger.showSnackBar(const SnackBar(content: Text('Signed out')));
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([session, appSettings]),
          builder: (context, _) {
            final account = session.account;
            final dark = Theme.of(context).brightness == Brightness.dark;
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _AccountHeader(
                  account: account,
                  onTap: () => _open(context, account == null ? const SignInPage() : const AccountPage()),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  onTap: () => _open(context, const SettingsPage()),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About'),
                  onTap: () => _open(context, const AboutPage()),
                ),
                const Divider(),
                SwitchListTile(
                  secondary: Icon(dark ? Icons.dark_mode : Icons.dark_mode_outlined),
                  title: const Text('Dark mode'),
                  value: dark,
                  onChanged: (on) => appSettings.setThemeMode(on ? ThemeMode.dark : ThemeMode.light),
                ),
                if (account == null)
                  ListTile(
                    leading: const Icon(Icons.login),
                    title: const Text('Sign in'),
                    onTap: () => _open(context, const SignInPage()),
                  )
                else
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Sign out'),
                    onTap: () => _signOut(context),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// Avatar, name and email of the account, or an invitation to sign in
class _AccountHeader extends StatelessWidget {
  final Account? account;
  final VoidCallback onTap;

  const _AccountHeader({required this.account, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    final account = this.account;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.all(design.padding),
        child: Row(
          children: [
            AccountAvatar(account: account, radius: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account?.name ?? 'Not signed in',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    account?.email ?? 'Sign in or create an account',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: design.muted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: design.icon),
          ],
        ),
      ),
    );
  }
}

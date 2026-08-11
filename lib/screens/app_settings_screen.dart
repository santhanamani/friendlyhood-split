import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/theme_controller.dart';
import 'about_screen.dart';

class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({
    super.key,
    required this.user,
    required this.themeController,
  });

  final User user;
  final AppThemeController themeController;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('App settings',
              style: TextStyle(fontWeight: FontWeight.w900)),
        ),
        body: AnimatedBuilder(
          animation: themeController,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
            children: [
              _sectionTitle(context, 'Appearance'),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: AppThemePreference.values
                        .map((preference) => _ThemeOption(
                              preference: preference,
                              selected:
                                  themeController.preference == preference,
                              onTap: () =>
                                  themeController.setPreference(preference),
                            ))
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  themeController.preference == AppThemePreference.system
                      ? 'BroSplit currently follows your phone light or dark mode.'
                      : '${themeController.preference.label} stays active even when your phone appearance changes.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _sectionTitle(context, 'Account'),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 27,
                      backgroundImage: user.photoURL?.isNotEmpty == true
                          ? NetworkImage(user.photoURL!)
                          : null,
                      child: user.photoURL?.isNotEmpty == true
                          ? null
                          : Text((user.displayName ?? 'F')[0].toUpperCase()),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.displayName ?? 'Friend',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 3),
                          Text(user.email ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 22),
              _sectionTitle(context, 'General'),
              const SizedBox(height: 10),
              Card(
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('Copy member ID'),
                    subtitle: const Text('Use it to identify your account'),
                    trailing: const Icon(Icons.copy_rounded),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: user.uid));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Member ID copied'),
                          duration: Duration(milliseconds: 2500),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text('About BroSplit'),
                    subtitle: const Text('Version, vision and mission'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AboutScreen()),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 26),
              OutlinedButton.icon(
                onPressed: () => _confirmSignOut(context),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _sectionTitle(BuildContext context, String title) => Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w900),
      );

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign in again with your Google account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) await AuthService().signOut();
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.preference,
    required this.selected,
    required this.onTap,
  });

  final AppThemePreference preference;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected
            ? colors.primaryContainer.withValues(alpha: .7)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected
                      ? colors.primary.withValues(alpha: .14)
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(preference.icon,
                    color: selected ? colors.primary : colors.onSurfaceVariant),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(preference.label,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(preference.description,
                        style: TextStyle(
                            color: colors.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? colors.primary : colors.outline,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

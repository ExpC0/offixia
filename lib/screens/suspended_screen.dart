import 'package:flutter/material.dart';

import '../models/organization.dart';
import '../services/auth_service.dart';

/// Shown to someone whose employee record has been switched off.
///
/// Their data is intact and their membership still points at the company --
/// this is offboarding, not deletion, so HR can reverse it.
class SuspendedScreen extends StatelessWidget {
  const SuspendedScreen({super.key, required this.organization});

  final Organization organization;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 52, color: scheme.outline),
                const SizedBox(height: 20),
                Text(
                  'Your access is paused',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  'Your account at ${organization.name} has been deactivated. '
                  'Contact HR if you think this is a mistake.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: AuthService.instance.signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

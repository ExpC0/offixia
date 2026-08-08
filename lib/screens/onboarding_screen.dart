import 'package:flutter/material.dart';

import '../format.dart';
import '../models/organization.dart';
import '../services/auth_service.dart';
import '../services/organization_service.dart';
import '../theme.dart';

/// Signed in, but not part of a company yet. Either start one -- becoming its
/// owner -- or join an existing one with an invite code.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();

  int _workdayStartMinutes = 9 * 60;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      // On success the membership listener swaps this screen out, so there is
      // deliberately nothing to do here.
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickWorkdayStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _workdayStartMinutes ~/ 60,
        minute: _workdayStartMinutes % 60,
      ),
      helpText: 'Workday starts at',
    );
    if (picked != null) {
      final minutes = picked.hour * 60 + picked.minute;
      if (!Organization.isValidStart(minutes)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Choose a start between 8:00 and 9:00 AM.'),
          ),
        );
        return;
      }
      setState(() => _workdayStartMinutes = minutes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Get started'),
          actions: [
            TextButton(
              onPressed: _busy ? null : AuthService.instance.signOut,
              child: const Text('Sign out'),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Join a team'),
              Tab(text: 'Create one'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _pane(
              icon: Icons.group_add_outlined,
              title: 'Join your team',
              subtitle:
                  'Ask your manager or HR for the six-character invite code.',
              children: [
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  style: const TextStyle(
                    fontSize: 24,
                    letterSpacing: 8,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    hintText: 'ABC123',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => OrganizationService.instance.joinWithCode(
                            _codeController.text,
                          ),
                        ),
                  child: Text(_busy ? 'Joining...' : 'Join'),
                ),
              ],
            ),
            _pane(
              icon: Icons.apartment_rounded,
              title: 'Create an organization',
              subtitle:
                  'You will be its owner, and can invite everyone else with '
                  'the code generated for you.',
              children: [
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Organization name',
                    hintText: 'Acme Ltd',
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: const Text('Workday starts at'),
                  subtitle: Text(
                    '${Fmt.minutesAsTime(_workdayStartMinutes)}–'
                    '${Fmt.minutesAsTime(_workdayStartMinutes + Organization.officeDuration.inMinutes)} '
                    '· 8 hrs work + 1 hr lunch',
                  ),
                  trailing: TextButton(
                    onPressed: _busy ? null : _pickWorkdayStart,
                    child: const Text('Change'),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => OrganizationService.instance.createOrganization(
                            name: _nameController.text,
                            workdayStartMinutes: _workdayStartMinutes,
                          ),
                        ),
                  child: Text(_busy ? 'Creating...' : 'Create organization'),
                ),
              ],
            ),
          ],
        ),
        bottomNavigationBar: _error == null
            ? null
            : Container(
                width: double.infinity,
                color: AppTheme.negative.withValues(alpha: 0.12),
                padding: const EdgeInsets.all(16),
                child: SafeArea(
                  top: false,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 18,
                        color: AppTheme.negative,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _pane({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 40, color: AppTheme.seed),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 28),
          ...children,
        ],
      ),
    );
  }
}

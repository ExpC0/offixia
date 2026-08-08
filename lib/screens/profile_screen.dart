import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models/employee.dart';
import '../models/organization.dart';
import '../services/auth_service.dart';
import '../services/employee_service.dart';
import '../services/location_service.dart';
import '../services/organization_service.dart';
import '../services/theme_service.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/status_chip.dart';
import '../widgets/ui.dart';

/// Your own details, the org's invite code, appearance, and sign-out.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.organization,
    required this.me,
  });

  final Organization organization;
  final Employee me;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('You')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(
            child: Column(
              children: [
                Avatar(employee: me, radius: 40),
                const SizedBox(height: 14),
                Text(
                  me.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  me.email,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                StatusChip.role(me.role),
              ],
            ),
          ),
          const SizedBox(height: 26),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit my details'),
                  subtitle: const Text('Name, job title, department, phone'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _EditProfileScreen(
                        organization: organization,
                        me: me,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.apartment_outlined),
                  title: const Text('Organization'),
                  subtitle: Text(
                    '${organization.name} · '
                    '${Fmt.minutesAsTime(organization.workdayStartMinutes)}–'
                    '${Fmt.minutesAsTime(organization.workdayEndMinutes)}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (me.managesPeople)
            _InviteCard(
              organization: organization,
              canRotate: organization.ownerUid == me.uid,
            ),
          if (me.role.canEditOrgSettings) ...[
            const SizedBox(height: 16),
            _OrgSettingsCard(organization: organization),
          ],
          const SizedBox(height: 16),
          AppCard(
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Appearance',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: ThemeService.instance.mode,
                    builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('System'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Light'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (selection) =>
                          ThemeService.instance.set(selection.first),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _OrganizationExitCard(organization: organization, me: me),
          const Gap.md(),
          OutlinedButton.icon(
            onPressed: AuthService.instance.signOut,
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.negative),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _OrganizationExitCard extends StatefulWidget {
  const _OrganizationExitCard({required this.organization, required this.me});

  final Organization organization;
  final Employee me;

  @override
  State<_OrganizationExitCard> createState() => _OrganizationExitCardState();
}

class _OrganizationExitCardState extends State<_OrganizationExitCard> {
  bool _busy = false;

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave organization?'),
        content: Text(
          'You will lose access to ${widget.organization.name}. Your company records remain with the organization.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => OrganizationService.instance.leaveOrganization(
        orgId: widget.organization.id,
        uid: widget.me.uid,
      ),
    );
  }

  Future<void> _delete() async {
    final controller = TextEditingController();
    final confirmation = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete organization?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently deletes the organization and its company data. Type the organization name to confirm.',
            ),
            const Gap.md(),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(labelText: widget.organization.name),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (confirmation == null || !mounted) return;
    await _run(
      () => OrganizationService.instance.deleteOrganization(
        orgId: widget.organization.id,
        confirmationName: confirmation,
        expectedName: widget.organization.name,
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final negative = AppSurfaces.of(context).negative;
    try {
      await action();
      // Profile is pushed above the session gate. Membership removal changes
      // that gate to Create/Join; collapsing the old route reveals it at once
      // while keeping Google authentication intact for the next company.
      navigator.popUntil((route) => route.isFirst);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: negative,
        ),
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deletes = widget.me.role.canDeleteOrganization;
    final negative = AppSurfaces.of(context).negative;
    return AppCard(
      elevated: false,
      borderColor: negative.withValues(alpha: 0.35),
      child: Row(
        children: [
          IconBadge(
            icon: deletes ? Icons.delete_forever_outlined : Icons.exit_to_app,
            color: negative,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deletes ? 'Delete organization' : 'Leave organization',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  deletes
                      ? 'Permanently remove company data'
                      : 'Remove your access to this company',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _busy ? null : (deletes ? _delete : _leave),
            style: TextButton.styleFrom(foregroundColor: negative),
            child: Text(_busy ? 'Working…' : (deletes ? 'Delete' : 'Leave')),
          ),
        ],
      ),
    );
  }
}

class _InviteCard extends StatefulWidget {
  const _InviteCard({required this.organization, required this.canRotate});

  final Organization organization;
  final bool canRotate;

  @override
  State<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<_InviteCard> {
  bool _rotating = false;

  Future<void> _rotate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate a new invite code?'),
        content: const Text(
          'The current code will stop working immediately. Existing employees '
          'will stay connected, but you will need to share the new code with '
          'future joiners.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep current code'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Generate new code'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _rotating = true);
    final messenger = ScaffoldMessenger.of(context);
    final negative = AppSurfaces.of(context).negative;
    try {
      final code = await OrganizationService.instance.rotateJoinCode(
        widget.organization.id,
      );
      await Clipboard.setData(ClipboardData(text: code));
      messenger.showSnackBar(
        const SnackBar(content: Text('New invite code generated and copied.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: negative,
        ),
      );
    } finally {
      if (mounted) setState(() => _rotating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final organization = widget.organization;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Invite code',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'New joiners enter this on their first sign-in.',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      organization.joinCode,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 6,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: organization.joinCode),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invite code copied.')),
                    );
                  },
                ),
              ],
            ),
            if (widget.canRotate) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _rotating ? null : _rotate,
                  icon: _rotating
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(_rotating ? 'Generating…' : 'Generate new code'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Owner-only knobs: when the workday starts, and the check-in geofence.
class _OrgSettingsCard extends StatefulWidget {
  const _OrgSettingsCard({required this.organization});

  final Organization organization;

  @override
  State<_OrgSettingsCard> createState() => _OrgSettingsCardState();
}

class _OrgSettingsCardState extends State<_OrgSettingsCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.negative,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeWorkdayStart() async {
    final org = widget.organization;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: org.workdayStartMinutes ~/ 60,
        minute: org.workdayStartMinutes % 60,
      ),
      helpText: 'Workday starts at',
    );
    if (picked == null || !mounted) return;

    final minutes = picked.hour * 60 + picked.minute;
    if (!Organization.isValidStart(minutes)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a start between 8:00 and 9:00 AM.'),
        ),
      );
      return;
    }

    await _run(
      () => OrganizationService.instance.updateSettings(
        orgId: org.id,
        workdayStartMinutes: minutes,
      ),
      'Workday start updated.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final org = widget.organization;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Organization settings',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Workday starts'),
              subtitle: Text(
                '${Fmt.minutesAsTime(org.workdayStartMinutes)}–'
                '${Fmt.minutesAsTime(org.workdayEndMinutes)} '
                '· 8 hrs work + 1 hr lunch',
              ),
              trailing: TextButton(
                onPressed: _busy ? null : _changeWorkdayStart,
                child: const Text('Change'),
              ),
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: org.hasGeofence,
              title: const Text('Restrict check-in to the office'),
              subtitle: Text(
                org.hasGeofence
                    ? 'Within ${org.geofenceMetres} m of the saved location'
                    : 'Anyone can check in from anywhere',
              ),
              onChanged: _busy
                  ? null
                  : (value) => _toggleGeofence(value: value),
            ),
          ],
        ),
      ),
    );
  }

  /// Turning the geofence on pins it to wherever the owner is standing, which
  /// is the office in every realistic case and saves asking for coordinates.
  Future<void> _toggleGeofence({required bool value}) async {
    final org = widget.organization;

    if (!value) {
      await _run(
        () => OrganizationService.instance.updateSettings(
          orgId: org.id,
          geofenceMetres: 0,
        ),
        'Location restriction removed.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use your current location?'),
        content: const Text(
          'The office will be set to where you are now, and staff will have '
          'to be within 200 m of it to check in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Set office here'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _run(() async {
      final fix = await LocationService.instance.currentPosition();
      final position = fix.position;
      if (position == null) {
        throw Exception(fix.reason ?? 'Could not get your location.');
      }
      await OrganizationService.instance.updateSettings(
        orgId: org.id,
        officeLat: position.latitude,
        officeLng: position.longitude,
        geofenceMetres: 200,
      );
    }, 'Office location saved. Check-in is now restricted.');
  }
}

class _EditProfileScreen extends StatefulWidget {
  const _EditProfileScreen({required this.organization, required this.me});

  final Organization organization;
  final Employee me;

  @override
  State<_EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<_EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _jobTitle;
  late final TextEditingController _department;
  late final TextEditingController _phone;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.me.name);
    _jobTitle = TextEditingController(text: widget.me.jobTitle);
    _department = TextEditingController(text: widget.me.department);
    _phone = TextEditingController(text: widget.me.phone);
  }

  @override
  void dispose() {
    _name.dispose();
    _jobTitle.dispose();
    _department.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await EmployeeService.instance.updateOwnProfile(
        orgId: widget.organization.id,
        uid: widget.me.uid,
        name: _name.text,
        jobTitle: _jobTitle.text,
        department: _department.text,
        phone: _phone.text,
      );
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Details saved.')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.negative,
        ),
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _jobTitle,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Job title',
              hintText: 'Backend Engineer',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _department,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Department',
              hintText: 'Engineering',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving...' : 'Save'),
          ),
        ],
      ),
    );
  }
}

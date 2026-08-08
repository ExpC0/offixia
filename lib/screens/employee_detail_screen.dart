import 'package:flutter/material.dart';

import '../format.dart';
import '../models/employee.dart';
import '../models/call.dart';
import '../models/organization.dart';
import '../models/permission.dart';
import '../services/employee_service.dart';
import '../services/chat_service.dart';
import '../services/calls.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/status_chip.dart';
import '../widgets/ui.dart';
import 'chat_thread_screen.dart';

/// One person's record. HR and above also get the controls that change their
/// designation, reporting line and access; the GM and MD additionally get the
/// authority grants, which are the one way around the ladder.
class EmployeeDetailScreen extends StatelessWidget {
  const EmployeeDetailScreen({
    super.key,
    required this.organization,
    required this.me,
    required this.person,
  });

  final Organization organization;
  final Employee me;
  final Employee person;

  @override
  Widget build(BuildContext context) {
    // Watched rather than passed through, so an edit made on this screen is
    // reflected here immediately instead of after backing out.
    return StreamBuilder<Employee?>(
      stream: EmployeeService.instance.watch(organization.id, person.uid),
      initialData: person,
      builder: (context, snapshot) => _build(context, snapshot.data ?? person),
    );
  }

  Widget _build(BuildContext context, Employee current) {
    // Nobody administers themselves, and nobody touches someone at or above
    // their own rank.
    final outranks = current.uid != me.uid && current.role.rank < me.role.rank;
    final canAdminister = me.managesPeople && outranks;
    final canGrant = me.role.canGrantAuthority && outranks;

    var step = 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          FadeInUp(
            index: step++,
            child: _Header(person: current),
          ),
          if (current.uid != me.uid) ...[
            const Gap.md(),
            FadeInUp(
              index: step++,
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _message(context, current),
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: const Text('Message'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    tooltip: 'Audio call',
                    icon: const Icon(Icons.call_rounded),
                    onPressed: () => Calls.start(
                      context: context,
                      organization: organization,
                      me: me,
                      other: current,
                      kind: CallKind.audio,
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Video call',
                    icon: const Icon(Icons.videocam_rounded),
                    onPressed: () => Calls.start(
                      context: context,
                      organization: organization,
                      me: me,
                      other: current,
                      kind: CallKind.video,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Gap.lg(),
          FadeInUp(
            index: step++,
            child: _Details(person: current),
          ),

          if (canAdminister) ...[
            const Gap.lg(),
            FadeInUp(
              index: step++,
              child: const SectionHeader(title: 'Manage'),
            ),
            FadeInUp(
              index: step++,
              child: _ManagePanel(
                organization: organization,
                me: me,
                person: current,
              ),
            ),
          ],

          if (canGrant) ...[
            const Gap.lg(),
            FadeInUp(
              index: step++,
              child: const SectionHeader(title: 'Individual authority'),
            ),
            FadeInUp(
              index: step++,
              child: _AuthorityPanel(
                organization: organization,
                person: current,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _message(BuildContext context, Employee other) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await ChatService.instance.openDirect(
        orgId: organization.id,
        me: me,
        other: other,
      );
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatThreadScreen(
            organization: organization,
            me: me,
            chatId: id,
            fallbackTitle: other.name,
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppSurfaces.of(context).negative,
        ),
      );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.person});

  final Employee person;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Avatar(employee: person, radius: 44),
        const Gap.md(),
        Text(
          person.name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          person.role.fullTitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const Gap.sm(),
        Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: [
            StatusChip.role(person.role),
            if (!person.active)
              const StatusChip(label: 'Deactivated', tone: StatusTone.negative),
            for (final permission in Permission.values)
              if (person.isGranted(permission))
                StatusChip(
                  label: permission.label,
                  tone: StatusTone.violet,
                  dense: true,
                  icon: Icons.key_rounded,
                ),
          ],
        ),
      ],
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.person});

  final Employee person;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);

    final rows = <({IconData icon, String label, String value})>[
      if (person.employeeId.isNotEmpty)
        (
          icon: Icons.badge_rounded,
          label: 'Staff number',
          value: person.employeeId,
        ),
      (
        icon: Icons.mail_outline_rounded,
        label: 'Email',
        value: person.email.isEmpty ? '--' : person.email,
      ),
      (
        icon: Icons.phone_outlined,
        label: 'Phone',
        value: person.phone.isEmpty ? 'Not set' : person.phone,
      ),
      (
        icon: Icons.badge_outlined,
        label: 'Job title',
        value: person.jobTitle.isEmpty ? 'Not set' : person.jobTitle,
      ),
      (
        icon: Icons.apartment_outlined,
        label: 'Department',
        value: person.department.isEmpty ? 'Not set' : person.department,
      ),
      (
        icon: Icons.event_outlined,
        label: 'Joined',
        value: person.joinedAt == null ? '--' : Fmt.fullDate(person.joinedAt!),
      ),
    ];

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 56, color: surfaces.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Icon(
                    rows[i].icon,
                    size: 19,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rows[i].label,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          rows[i].value,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Designation, reporting line, and whether the person is still active.
class _ManagePanel extends StatefulWidget {
  const _ManagePanel({
    required this.organization,
    required this.me,
    required this.person,
  });

  final Organization organization;
  final Employee me;
  final Employee person;

  @override
  State<_ManagePanel> createState() => _ManagePanelState();
}

class _ManagePanelState extends State<_ManagePanel> {
  bool _busy = false;

  Future<void> _apply(Future<void> Function() action, String done) async {
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

  Future<void> _pickManager() async {
    final people = await EmployeeService.instance
        .directory(widget.organization.id)
        .first;
    if (!mounted) return;

    // Nobody reports to themselves, and only somebody who can actually approve
    // leave is a meaningful manager.
    final candidates = people
        .where(
          (candidate) =>
              candidate.uid != widget.person.uid &&
              candidate.active &&
              candidate.role.canApproveLeave,
        )
        .toList();

    final chosen = await showModalBottomSheet<_ManagerChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Reports to',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('No manager'),
              subtitle: const Text('Requests go to HR and above'),
              onTap: () =>
                  Navigator.of(context).pop(const _ManagerChoice(null)),
            ),
            const Divider(height: 1),
            if (candidates.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nobody holds a manager or higher designation yet. '
                  'Promote someone first.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final candidate in candidates)
                ListTile(
                  leading: Avatar(employee: candidate),
                  title: Text(candidate.name),
                  subtitle: Text(candidate.role.fullTitle),
                  onTap: () =>
                      Navigator.of(context).pop(_ManagerChoice(candidate)),
                ),
          ],
        ),
      ),
    );

    // Null means the sheet was dismissed; an explicit choice arrives wrapped,
    // so "no manager" and "changed my mind" stay distinguishable.
    if (chosen == null || !mounted) return;

    await _apply(
      () => EmployeeService.instance.updateAsAdmin(
        orgId: widget.organization.id,
        target: widget.person,
        managerUid: chosen.employee?.uid,
        clearManager: chosen.employee == null,
      ),
      chosen.employee == null
          ? 'Manager cleared.'
          : '${widget.person.name} now reports to ${chosen.employee!.name}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final assignable = widget.me.role.assignableRoles;
    final surfaces = AppSurfaces.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Designation', style: Theme.of(context).textTheme.titleSmall),
          const Gap.sm(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final role in assignable)
                ChoiceChip(
                  label: Text(role.label),
                  selected: widget.person.role == role,
                  onSelected: _busy
                      ? null
                      : (_) => _apply(
                          () => EmployeeService.instance.updateAsAdmin(
                            orgId: widget.organization.id,
                            target: widget.person,
                            role: role,
                          ),
                          '${widget.person.name} is now ${role.fullTitle}.',
                        ),
                ),
            ],
          ),
          const Gap.md(),
          Divider(color: surfaces.border),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.supervisor_account_outlined),
            title: const Text('Reports to'),
            subtitle: Text(
              widget.person.managerUid == null
                  ? 'Nobody set'
                  : 'A manager is assigned',
            ),
            trailing: TextButton(
              onPressed: _busy ? null : _pickManager,
              child: const Text('Change'),
            ),
          ),
          Divider(color: surfaces.border),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: widget.person.active,
            onChanged: _busy
                ? null
                : (value) => _apply(
                    () => EmployeeService.instance.updateAsAdmin(
                      orgId: widget.organization.id,
                      target: widget.person,
                      active: value,
                    ),
                    value
                        ? '${widget.person.name} reactivated.'
                        : '${widget.person.name} deactivated.',
                  ),
            title: const Text('Active'),
            subtitle: const Text(
              'Turning this off blocks access without deleting history',
            ),
          ),
        ],
      ),
    );
  }
}

/// Wrapper so "chose nobody" and "dismissed the sheet" stay distinguishable
/// through a nullable return.
class _ManagerChoice {
  const _ManagerChoice(this.employee);
  final Employee? employee;
}

/// Authorities handed to this person individually, bypassing the ladder.
/// GM and MD only.
class _AuthorityPanel extends StatefulWidget {
  const _AuthorityPanel({required this.organization, required this.person});

  final Organization organization;
  final Employee person;

  @override
  State<_AuthorityPanel> createState() => _AuthorityPanelState();
}

class _AuthorityPanelState extends State<_AuthorityPanel> {
  bool _busy = false;

  Future<void> _toggle(Permission permission, bool on) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final next = {...widget.person.grants};
    if (on) {
      next.add(permission);
    } else {
      next.remove(permission);
    }

    try {
      await EmployeeService.instance.setGrants(
        orgId: widget.organization.id,
        target: widget.person,
        grants: next,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            on
                ? '${widget.person.name} can now ${permission.label.toLowerCase()}.'
                : '${permission.label} removed from ${widget.person.name}.',
          ),
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.key_rounded,
                color: const Color(0xFF9B7DEA),
                size: 34,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  'Give ${widget.person.name.split(' ').first} an authority '
                  'their designation does not include.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const Gap.md(),
          for (var i = 0; i < Permission.values.length; i++) ...[
            if (i > 0) Divider(color: surfaces.border, height: 20),
            _AuthorityRow(
              permission: Permission.values[i],
              fromRole: widget.person.role.confers(Permission.values[i]),
              granted: widget.person.grants.contains(Permission.values[i]),
              busy: _busy,
              onChanged: (value) => _toggle(Permission.values[i], value),
              scheme: scheme,
            ),
          ],
        ],
      ),
    );
  }
}

class _AuthorityRow extends StatelessWidget {
  const _AuthorityRow({
    required this.permission,
    required this.fromRole,
    required this.granted,
    required this.busy,
    required this.onChanged,
    required this.scheme,
  });

  final Permission permission;
  final bool fromRole;
  final bool granted;
  final bool busy;
  final ValueChanged<bool> onChanged;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    // The switch reflects the *individual grant* only, never the designation.
    //
    // It used to show `fromRole || granted` and disable itself whenever the
    // designation covered the authority. That made a grant impossible to take
    // back the moment someone was promoted into a designation including it:
    // the grant stayed on the record and the switch was locked on. What the
    // designation confers is stated in the subtitle instead, where it belongs.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      permission.label,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (fromRole) ...[
                    const SizedBox(width: 7),
                    Icon(
                      Icons.workspace_premium_rounded,
                      size: 14,
                      color: scheme.primary,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                fromRole
                    ? (granted
                          ? 'Their designation already covers this, so the '
                                'grant is redundant -- you can switch it off.'
                          : 'Included in their designation')
                    : permission.description,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: fromRole ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          value: granted,
          onChanged: busy ? null : onChanged,
        ),
      ],
    );
  }
}

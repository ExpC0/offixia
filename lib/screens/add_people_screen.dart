import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/employee.dart';
import '../models/invite.dart';
import '../models/organization.dart';
import '../models/role.dart';
import '../services/employee_service.dart';
import '../services/invite_service.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/status_chip.dart';
import '../widgets/ui.dart';

/// Bringing people into the company, by email or by staff number.
///
/// The app cannot create somebody else's login -- only they can, by signing in
/// with Google -- so inviting records the designation and department waiting
/// for that address. The moment they sign in, they land inside the company
/// with all of it applied and never see the invite-code screen.
class AddPeopleScreen extends StatefulWidget {
  const AddPeopleScreen({
    super.key,
    required this.organization,
    required this.me,
  });

  final Organization organization;
  final Employee me;

  @override
  State<AddPeopleScreen> createState() => _AddPeopleScreenState();
}

class _AddPeopleScreenState extends State<AddPeopleScreen> {
  final _email = TextEditingController();
  final _department = TextEditingController();
  final _jobTitle = TextEditingController();
  final _staffNumber = TextEditingController();

  late final Stream<List<Invite>> _pending;
  late final Stream<List<Employee>> _people;

  Role _role = Role.employee;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pending = InviteService.instance.pending(widget.organization.id);
    _people = EmployeeService.instance.directory(widget.organization.id);
  }

  @override
  void dispose() {
    _email.dispose();
    _department.dispose();
    _jobTitle.dispose();
    _staffNumber.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final negative = AppSurfaces.of(context).negative;
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: negative,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invite() async {
    final email = _email.text;
    await _run(
      () => InviteService.instance.invite(
        organization: widget.organization,
        invitedBy: widget.me,
        email: email,
        role: _role,
        department: _department.text,
        jobTitle: _jobTitle.text,
      ),
      'Invited ${email.trim()}. They join automatically when they sign in.',
    );
    if (mounted) {
      _email.clear();
      _department.clear();
      _jobTitle.clear();
    }
  }

  /// Bringing back somebody who was deactivated. Their staff number is the
  /// handle people actually remember, which is the whole reason it exists.
  Future<void> _reactivate(List<Employee> everyone) async {
    final wanted = _staffNumber.text.trim().toUpperCase();
    if (wanted.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a staff number.')),
      );
      return;
    }

    final match = everyone
        .where((person) => person.employeeId.toUpperCase() == wanted)
        .firstOrNull;

    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No staff number $wanted in this company.')),
      );
      return;
    }
    if (match.active) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${match.name} is already active.')),
      );
      return;
    }

    await _run(
      () => EmployeeService.instance.updateAsAdmin(
        orgId: widget.organization.id,
        target: match,
        active: true,
      ),
      '${match.name} reactivated.',
    );
    if (mounted) _staffNumber.clear();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // You can never invite into a designation at or above your own; the rules
    // enforce it, and offering the option would only produce a rejection.
    final assignable = Role.values
        .where((role) => role.rank < widget.me.role.rank)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Add people')),
      body: StreamBuilder<List<Employee>>(
        stream: _people,
        builder: (context, peopleSnapshot) {
          final everyone = peopleSnapshot.data ?? const <Employee>[];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconBadge(
                          icon: Icons.mail_outline_rounded,
                          color: scheme.primary,
                          size: 34,
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            'Invite by email',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const Gap.xs(),
                    Text(
                      'They join the moment they sign in with this address, '
                      'already set up as you choose below. No invite code '
                      'needed.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Gap.md(),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Work email',
                        hintText: 'name@company.com',
                      ),
                    ),
                    const Gap.sm(),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _jobTitle,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Job title',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _department,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Department',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Gap.md(),
                    Text(
                      'Designation',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Gap.xs(),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final role in assignable)
                          ChoiceChip(
                            label: Text(role.label),
                            selected: _role == role,
                            onSelected: (_) => setState(() => _role = role),
                          ),
                      ],
                    ),
                    const Gap.md(),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _invite,
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: Text(_busy ? 'Working...' : 'Send invite'),
                      ),
                    ),
                  ],
                ),
              ),

              const Gap.lg(),
              const SectionHeader(title: 'Bring someone back'),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Somebody deactivated keeps their staff number and their '
                      'whole history. Enter it to switch them back on.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Gap.sm(),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _staffNumber,
                            textCapitalization: TextCapitalization.characters,
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: 'Staff number',
                              hintText:
                                  '${widget.organization.employeeIdPrefix}0084',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.tonal(
                          onPressed: _busy
                              ? null
                              : () => _reactivate(everyone),
                          child: const Text('Reactivate'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Gap.lg(),
              _InviteCodeCard(organization: widget.organization),

              const Gap.lg(),
              const SectionHeader(title: 'Waiting to arrive'),
              StreamBuilder<List<Invite>>(
                stream: _pending,
                builder: (context, snapshot) {
                  final invites = snapshot.data ?? const <Invite>[];
                  if (invites.isEmpty) {
                    return AppCard(
                      elevated: false,
                      child: Text(
                        'Nobody is pending. Invited people disappear from here '
                        'the moment they sign in.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  }

                  return AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < invites.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: 16,
                              color: AppSurfaces.of(context).border,
                            ),
                          ListTile(
                            leading: IconBadge(
                              icon: Icons.hourglass_empty_rounded,
                              color: AppSurfaces.of(context).caution,
                              size: 36,
                            ),
                            title: Text(
                              invites[i].email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            subtitle: Text(
                              invites[i].jobTitle.isEmpty
                                  ? invites[i].role.fullTitle
                                  : '${invites[i].jobTitle} · '
                                        '${invites[i].role.label}',
                            ),
                            trailing: IconButton(
                              tooltip: 'Withdraw',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _busy
                                  ? null
                                  : () => _run(
                                      () => InviteService.instance.revoke(
                                        email: invites[i].email,
                                      ),
                                      'Invite withdrawn.',
                                    ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),

              const Gap.lg(),
              const SectionHeader(title: 'Deactivated'),
              _DeactivatedList(
                organization: widget.organization,
                me: widget.me,
                everyone: everyone,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InviteCodeCard extends StatelessWidget {
  const _InviteCodeCard({required this.organization});

  final Organization organization;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Or share the invite code',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            'Anyone with this can join as an Employee.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Gap.sm(),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    organization.joinCode,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 5,
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
        ],
      ),
    );
  }
}

class _DeactivatedList extends StatelessWidget {
  const _DeactivatedList({
    required this.organization,
    required this.me,
    required this.everyone,
  });

  final Organization organization;
  final Employee me;
  final List<Employee> everyone;

  @override
  Widget build(BuildContext context) {
    final off = everyone.where((person) => !person.active).toList();

    if (off.isEmpty) {
      return AppCard(
        elevated: false,
        child: Text(
          'Everyone on the staff list is active.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < off.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 68,
                color: AppSurfaces.of(context).border,
              ),
            ListTile(
              leading: Avatar(employee: off[i]),
              title: Text(
                off[i].name,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              subtitle: Text(
                off[i].employeeId.isEmpty
                    ? 'Deactivated'
                    : '${off[i].employeeId} · deactivated',
              ),
              trailing: StatusChip.role(off[i].role),
            ),
          ],
        ],
      ),
    );
  }
}

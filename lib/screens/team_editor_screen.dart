import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../models/organization.dart';
import '../models/team.dart';
import '../services/employee_service.dart';
import '../services/team_service.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/status_chip.dart';
import '../widgets/ui.dart';

/// Forming a team, or editing one. GM only, enforced by the rules.
///
/// The member picker deliberately shows the entire company rather than one
/// department: a team that could only be drawn from a single reporting line
/// would not be worth having.
class TeamEditorScreen extends StatefulWidget {
  const TeamEditorScreen({
    super.key,
    required this.organization,
    required this.me,
    this.existing,
  });

  final Organization organization;
  final Employee me;
  final Team? existing;

  @override
  State<TeamEditorScreen> createState() => _TeamEditorScreenState();
}

class _TeamEditorScreenState extends State<TeamEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final Stream<List<Employee>> _people;

  final Set<String> _picked = {};
  String? _leadUid;
  bool _busy = false;
  String _query = '';

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _description = TextEditingController(
      text: widget.existing?.description ?? '',
    );
    _picked.addAll(widget.existing?.memberUids ?? const []);
    _leadUid = widget.existing?.leadUid;
    _people = EmployeeService.instance.directory(widget.organization.id);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save(List<Employee> everyone) async {
    if (_picked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one member.')),
      );
      return;
    }

    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final negative = AppSurfaces.of(context).negative;

    try {
      final members = everyone
          .where((person) => _picked.contains(person.uid))
          .toList();
      final lead = everyone.where((p) => p.uid == _leadUid).firstOrNull;

      if (_isEdit) {
        final team = widget.existing!;
        await TeamService.instance.update(
          orgId: widget.organization.id,
          teamId: team.id,
          name: _name.text,
          description: _description.text,
        );

        // Reconcile the roster: the picker works on a set, the service takes
        // the two deltas, and doing it here keeps the service honest about
        // what actually changed.
        final added = _picked.difference(team.memberUids.toSet());
        final removed = team.memberUids.toSet().difference(_picked);

        if (added.isNotEmpty) {
          await TeamService.instance.addMembers(
            orgId: widget.organization.id,
            teamId: team.id,
            uids: added.toList(),
          );
        }
        for (final uid in removed) {
          await TeamService.instance.removeMember(
            orgId: widget.organization.id,
            teamId: team.id,
            uid: uid,
            currentLeadUid: team.leadUid,
          );
        }
        if (_leadUid != team.leadUid) {
          await TeamService.instance.setLead(
            orgId: widget.organization.id,
            teamId: team.id,
            uid: _leadUid,
          );
        }
      } else {
        await TeamService.instance.create(
          orgId: widget.organization.id,
          createdBy: widget.me,
          name: _name.text,
          description: _description.text,
          members: members,
          lead: lead,
        );
      }

      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Team updated.' : 'Team created.')),
      );
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
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<List<Employee>>(
      stream: _people,
      builder: (context, snapshot) {
        final everyone = (snapshot.data ?? const <Employee>[])
            .where((person) => person.active)
            .toList();

        final needle = _query.trim().toLowerCase();
        final visible = needle.isEmpty
            ? everyone
            : everyone
                  .where(
                    (person) =>
                        person.name.toLowerCase().contains(needle) ||
                        person.department.toLowerCase().contains(needle) ||
                        person.jobTitle.toLowerCase().contains(needle),
                  )
                  .toList();

        return Scaffold(
          appBar: AppBar(title: Text(_isEdit ? 'Edit team' : 'New team')),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                onPressed: _busy ? null : () => _save(everyone),
                child: Text(
                  _busy
                      ? 'Saving...'
                      : (_isEdit
                            ? 'Save changes'
                            : 'Create team (${_picked.length})'),
                ),
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Team name',
                  hintText: 'Platform, Launch squad, Night shift',
                ),
              ),
              const Gap.sm(),
              TextField(
                controller: _description,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What it is for (optional)',
                ),
              ),
              const Gap.lg(),
              SectionHeader(
                title: 'Members',
                trailing: Text(
                  '${_picked.length} selected',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  hintText: 'Search anyone in the company',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const Gap.sm(),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Nobody matches "$_query".',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < visible.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            indent: 68,
                            color: AppSurfaces.of(context).border,
                          ),
                        CheckboxListTile(
                          value: _picked.contains(visible[i].uid),
                          onChanged: (value) => setState(() {
                            if (value == true) {
                              _picked.add(visible[i].uid);
                            } else {
                              _picked.remove(visible[i].uid);
                              // Somebody removed from the team cannot stay its
                              // lead.
                              if (_leadUid == visible[i].uid) _leadUid = null;
                            }
                          }),
                          secondary: Avatar(employee: visible[i]),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  visible[i].name,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleSmall,
                                ),
                              ),
                              const SizedBox(width: 6),
                              StatusChip.role(visible[i].role),
                            ],
                          ),
                          subtitle: Text(visible[i].subtitle),
                        ),
                      ],
                    ],
                  ),
                ),
              const Gap.lg(),
              SectionHeader(title: 'Team lead'),
              Text(
                'Optional, and carries no extra permissions. It only marks who '
                'runs the team.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Gap.sm(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Nobody'),
                    selected: _leadUid == null,
                    onSelected: (_) => setState(() => _leadUid = null),
                  ),
                  for (final person in everyone.where(
                    (p) => _picked.contains(p.uid),
                  ))
                    ChoiceChip(
                      avatar: Avatar(employee: person, radius: 10),
                      label: Text(person.name.split(' ').first),
                      selected: _leadUid == person.uid,
                      onSelected: (_) =>
                          setState(() => _leadUid = person.uid),
                    ),
                ],
              ),
              if (_picked.isEmpty) ...[
                const Gap.sm(),
                Text(
                  'Pick members first to choose a lead.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

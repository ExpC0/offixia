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
import 'employee_detail_screen.dart';
import 'team_editor_screen.dart';

/// One team: who is in it, and the controls to change that.
class TeamDetailScreen extends StatelessWidget {
  const TeamDetailScreen({
    super.key,
    required this.organization,
    required this.me,
    required this.teamId,
  });

  final Organization organization;
  final Employee me;
  final String teamId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Team?>(
      stream: TeamService.instance.watch(organization.id, teamId),
      builder: (context, snapshot) {
        final team = snapshot.data;

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Team')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        // Deleted while somebody had it open.
        if (team == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Team')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'This team no longer exists.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        return _TeamBody(
          organization: organization,
          me: me,
          team: team,
        );
      },
    );
  }
}

class _TeamBody extends StatefulWidget {
  const _TeamBody({
    required this.organization,
    required this.me,
    required this.team,
  });

  final Organization organization;
  final Employee me;
  final Team team;

  @override
  State<_TeamBody> createState() => _TeamBodyState();
}

class _TeamBodyState extends State<_TeamBody> {
  late final Stream<List<Employee>> _people;
  bool _busy = false;

  bool get _canManage => widget.me.managesTeams;

  @override
  void initState() {
    super.initState();
    _people = EmployeeService.instance.directory(widget.organization.id);
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

  Future<void> _remove(Employee person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${person.name.split(' ').first}?'),
        content: Text(
          'They stay in the company and keep everything else. This only takes '
          'them out of ${widget.team.name}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _run(
      () => TeamService.instance.removeMember(
        orgId: widget.organization.id,
        teamId: widget.team.id,
        uid: person.uid,
        currentLeadUid: widget.team.leadUid,
      ),
      '${person.name} removed from the team.',
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this team?'),
        content: Text(
          '"${widget.team.name}" is removed for everyone. Nobody loses their '
          'job, their records or any access, since a team grants none.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppSurfaces.of(dialogContext).negative,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final navigator = Navigator.of(context);
    await _run(
      () => TeamService.instance.delete(
        orgId: widget.organization.id,
        teamId: widget.team.id,
      ),
      'Team deleted.',
    );
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final team = widget.team;
    final scheme = Theme.of(context).colorScheme;
    final surfaces = AppSurfaces.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team'),
        actions: [
          if (_canManage)
            IconButton(
              tooltip: 'Edit team',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TeamEditorScreen(
                          organization: widget.organization,
                          me: widget.me,
                          existing: team,
                        ),
                      ),
                    ),
            ),
        ],
      ),
      body: StreamBuilder<List<Employee>>(
        stream: _people,
        builder: (context, snapshot) {
          final everyone = snapshot.data ?? const <Employee>[];
          final byUid = {for (final person in everyone) person.uid: person};

          // Lead first, then alphabetical -- the roster should open with
          // whoever runs the team.
          final members =
              team.memberUids
                  .map((uid) => byUid[uid])
                  .whereType<Employee>()
                  .toList()
                ..sort((a, b) {
                  if (a.uid == team.leadUid) return -1;
                  if (b.uid == team.leadUid) return 1;
                  return a.name.compareTo(b.name);
                });

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Center(
                child: Column(
                  children: [
                    IconBadge(
                      icon: Icons.workspaces_rounded,
                      color: scheme.primary,
                      size: 68,
                    ),
                    const Gap.md(),
                    Text(
                      team.name,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${team.size} ${team.size == 1 ? 'member' : 'members'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (team.description.isNotEmpty) ...[
                      const Gap.sm(),
                      Text(
                        team.description,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
              const Gap.lg(),
              const SectionHeader(title: 'Members'),
              if (members.isEmpty)
                const AppCard(child: Text('Nobody in this team yet.'))
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < members.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            indent: 68,
                            color: surfaces.border,
                          ),
                        ListTile(
                          leading: Avatar(employee: members[i]),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  members[i].name,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleSmall,
                                ),
                              ),
                              if (members[i].uid == team.leadUid) ...[
                                const SizedBox(width: 6),
                                const StatusChip(
                                  label: 'Lead',
                                  tone: StatusTone.brand,
                                  dense: true,
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(members[i].subtitle),
                          trailing: _canManage && members.length > 1
                              ? IconButton(
                                  tooltip: 'Remove from team',
                                  icon: Icon(
                                    Icons.remove_circle_outline_rounded,
                                    color: surfaces.negative,
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () => _remove(members[i]),
                                )
                              : null,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => EmployeeDetailScreen(
                                organization: widget.organization,
                                me: widget.me,
                                person: members[i],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (_canManage) ...[
                const Gap.lg(),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: surfaces.negative,
                    ),
                    title: Text(
                      'Delete team',
                      style: TextStyle(color: surfaces.negative),
                    ),
                    subtitle: const Text('Removes the grouping, nothing else'),
                    onTap: _busy ? null : _delete,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

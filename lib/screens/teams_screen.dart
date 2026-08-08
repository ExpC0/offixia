import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../models/organization.dart';
import '../models/team.dart';
import '../services/employee_service.dart';
import '../services/team_service.dart';
import '../widgets/avatar.dart';
import '../widgets/empty_state.dart';
import '../widgets/ui.dart';
import 'team_detail_screen.dart';
import 'team_editor_screen.dart';

/// Every team in the company. Anyone can look; only the GM can form one.
class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key, required this.organization, required this.me});

  final Organization organization;
  final Employee me;

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  late final Stream<List<Team>> _teams;
  late final Stream<List<Employee>> _people;

  @override
  void initState() {
    super.initState();
    _teams = TeamService.instance.all(widget.organization.id);
    _people = EmployeeService.instance.directory(widget.organization.id);
  }

  @override
  Widget build(BuildContext context) {
    final canManage = widget.me.managesTeams;

    return Scaffold(
      appBar: AppBar(title: const Text('Teams')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TeamEditorScreen(
                    organization: widget.organization,
                    me: widget.me,
                  ),
                ),
              ),
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('New team'),
            )
          : null,
      body: StreamBuilder<List<Employee>>(
        stream: _people,
        builder: (context, peopleSnapshot) {
          final people = {
            for (final person in peopleSnapshot.data ?? const <Employee>[])
              person.uid: person,
          };

          return StreamBuilder<List<Team>>(
            stream: _teams,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const ErrorState(message: 'Could not load teams.');
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final teams = snapshot.data ?? const <Team>[];
              if (teams.isEmpty) {
                return EmptyState(
                  icon: Icons.workspaces_outline,
                  title: 'No teams yet',
                  message: canManage
                      ? 'Group people from anywhere in the company into a '
                            'team, whatever their department or designation.'
                      : 'Your GM has not set any teams up yet.',
                );
              }

              // Yours first: the ones you are in are the ones you came to see.
              final mine = teams
                  .where((team) => team.includes(widget.me.uid))
                  .toList();
              final others = teams
                  .where((team) => !team.includes(widget.me.uid))
                  .toList();

              return ListView(
                padding: EdgeInsets.fromLTRB(16, 12, 16, canManage ? 96 : 24),
                children: [
                  if (mine.isNotEmpty) ...[
                    const SectionHeader(title: 'My teams'),
                    for (var i = 0; i < mine.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: FadeInUp(
                          index: i,
                          child: _TeamCard(
                            organization: widget.organization,
                            me: widget.me,
                            team: mine[i],
                            people: people,
                          ),
                        ),
                      ),
                    const Gap.md(),
                  ],
                  if (others.isNotEmpty) ...[
                    SectionHeader(
                      title: mine.isEmpty ? 'All teams' : 'Other teams',
                    ),
                    for (var i = 0; i < others.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: FadeInUp(
                          index: mine.length + i,
                          child: _TeamCard(
                            organization: widget.organization,
                            me: widget.me,
                            team: others[i],
                            people: people,
                          ),
                        ),
                      ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.organization,
    required this.me,
    required this.team,
    required this.people,
  });

  final Organization organization;
  final Employee me;
  final Team team;
  final Map<String, Employee> people;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lead = team.leadUid == null ? null : people[team.leadUid];

    // A few faces say more about a team than a number does.
    final faces = team.memberUids
        .map((uid) => people[uid])
        .whereType<Employee>()
        .take(4)
        .toList();

    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TeamDetailScreen(
            organization: organization,
            me: me,
            teamId: team.id,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.workspaces_rounded,
                color: scheme.primary,
                size: 38,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lead == null
                          ? '${team.size} '
                                '${team.size == 1 ? 'member' : 'members'}'
                          : '${team.size} · led by ${lead.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (team.includes(me.uid))
                const StatusChipYou(),
            ],
          ),
          if (team.description.isNotEmpty) ...[
            const Gap.sm(),
            Text(
              team.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (faces.isNotEmpty) ...[
            const Gap.sm(),
            Row(
              children: [
                for (final person in faces)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Avatar(employee: person, radius: 13),
                  ),
                if (team.size > faces.length)
                  Text(
                    '+${team.size - faces.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A small "you're in this" marker.
class StatusChipYou extends StatelessWidget {
  const StatusChipYou({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Text(
        'You',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: scheme.primary,
        ),
      ),
    );
  }
}

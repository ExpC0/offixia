import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../models/organization.dart';
import '../models/role.dart';
import '../models/team.dart';
import '../services/employee_service.dart';
import '../services/team_service.dart';
import '../widgets/avatar.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_chip.dart';
import '../widgets/ui.dart';
import 'add_people_screen.dart';
import 'employee_detail_screen.dart';
import 'teams_screen.dart';
import 'team_detail_screen.dart';

/// Everyone at the company, searchable, grouped by department.
class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({
    super.key,
    required this.organization,
    required this.me,
  });

  final Organization organization;
  final Employee me;

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.organization.name),
        actions: [
          if (widget.me.invitesEmployees)
            IconButton(
              tooltip: 'Add people',
              icon: const Icon(Icons.person_add_alt_1_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AddPeopleScreen(
                    organization: widget.organization,
                    me: widget.me,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Teams',
            icon: const Icon(Icons.workspaces_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TeamsScreen(
                  organization: widget.organization,
                  me: widget.me,
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search name, staff number, department',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<Employee>>(
        stream: EmployeeService.instance.directory(widget.organization.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ErrorState(message: 'Could not load the directory.');
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = snapshot.data ?? const <Employee>[];
          final people = _filter(all);

          if (people.isEmpty) {
            return EmptyState(
              icon: Icons.person_search_outlined,
              title: _query.isEmpty ? 'Nobody here yet' : 'No match',
              message: _query.isEmpty
                  ? 'Share your invite code so the team can join.'
                  : 'Nobody matches "$_query".',
            );
          }

          final grouped = _groupByDepartment(people);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              // Teams inline rather than behind the toolbar icon: they are the
              // shape of the company, and needing a tap to see them made the
              // directory read as a flat address book.
              _TeamStrip(organization: widget.organization, me: widget.me),
              for (final entry in grouped.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                  child: Text(
                    entry.key.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < entry.value.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: 70, endIndent: 12),
                        _PersonRow(
                          organization: widget.organization,
                          me: widget.me,
                          person: entry.value[i],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  List<Employee> _filter(List<Employee> all) {
    if (_query.trim().isEmpty) return all;
    final needle = _query.toLowerCase().trim();
    return all
        .where(
          (person) =>
              person.name.toLowerCase().contains(needle) ||
              person.employeeId.toLowerCase().contains(needle) ||
              person.email.toLowerCase().contains(needle) ||
              person.jobTitle.toLowerCase().contains(needle) ||
              person.department.toLowerCase().contains(needle),
        )
        .toList();
  }

  /// Departments alphabetically, with the unassigned bucket last so an empty
  /// `department` field does not sort to the top under a blank heading.
  Map<String, List<Employee>> _groupByDepartment(List<Employee> people) {
    const noDepartment = 'No department';
    final buckets = <String, List<Employee>>{};

    for (final person in people) {
      final key = person.department.trim().isEmpty
          ? noDepartment
          : person.department.trim();
      buckets.putIfAbsent(key, () => []).add(person);
    }

    final keys = buckets.keys.toList()
      ..sort((a, b) {
        if (a == noDepartment) return 1;
        if (b == noDepartment) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    return {for (final key in keys) key: buckets[key]!};
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.organization,
    required this.me,
    required this.person,
  });

  final Organization organization;
  final Employee me;
  final Employee person;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Avatar(employee: person),
      title: Row(
        children: [
          Flexible(
            child: Text(
              person.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: person.active
                    ? null
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (person.uid == me.uid)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Text('(you)', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
      subtitle: Text(
        person.active
            ? (person.employeeId.isEmpty
                  ? person.subtitle
                  : '${person.employeeId} · ${person.subtitle}')
            : 'Deactivated',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: person.role == Role.employee
          ? null
          : StatusChip.role(person.role),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EmployeeDetailScreen(
            organization: organization,
            me: me,
            person: person,
          ),
        ),
      ),
    );
  }
}

/// The company's teams, across the top of the directory.
class _TeamStrip extends StatelessWidget {
  const _TeamStrip({required this.organization, required this.me});

  final Organization organization;
  final Employee me;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<List<Team>>(
      stream: TeamService.instance.all(organization.id),
      builder: (context, snapshot) {
        final teams = snapshot.data ?? const <Team>[];
        if (teams.isEmpty) return const SizedBox.shrink();

        // Yours first, since those are the ones you look for.
        final ordered = [
          ...teams.where((team) => team.includes(me.uid)),
          ...teams.where((team) => !team.includes(me.uid)),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: SectionHeader(title: 'Teams'),
            ),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: ordered.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final team = ordered[index];
                  final mine = team.includes(me.uid);

                  return SizedBox(
                    width: 168,
                    child: AppCard(
                      padding: const EdgeInsets.all(13),
                      color: mine
                          ? scheme.primary.withValues(alpha: 0.07)
                          : null,
                      borderColor: mine
                          ? scheme.primary.withValues(alpha: 0.32)
                          : null,
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Icon(
                            Icons.workspaces_rounded,
                            size: 20,
                            color: scheme.primary,
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                team.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(
                                '${team.size} '
                                '${team.size == 1 ? 'member' : 'members'}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const Gap.sm(),
          ],
        );
      },
    );
  }
}

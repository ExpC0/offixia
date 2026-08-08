import 'package:flutter/material.dart';

import '../format.dart';
import '../models/announcement.dart';
import '../models/attendance.dart';
import '../models/employee.dart';
import '../models/leave_request.dart';
import '../models/organization.dart';
import '../models/work_task.dart';
import '../services/announcement_service.dart';
import '../services/attendance_service.dart';
import '../services/employee_service.dart';
import '../services/leave_service.dart';
import '../services/task_service.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/punch_card.dart';
import '../widgets/status_chip.dart';
import '../widgets/ui.dart';
import 'announcements_screen.dart';
import 'approvals_screen.dart';
import 'profile_screen.dart';

/// The landing tab. Everyone gets the clock and their own work; what sits
/// between them depends on the designation -- an approvals queue for anyone
/// who signs things off, a company rollup for senior management.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.organization,
    required this.me,
    required this.onOpenTab,
  });

  final Organization organization;
  final Employee me;
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    var step = 0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            FadeInUp(
              index: step++,
              child: _Greeting(me: me, organization: organization),
            ),
            const Gap.md(),
            FadeInUp(
              index: step++,
              child: PunchCard(organization: organization, me: me),
            ),
            const Gap.lg(),

            if (me.role.canViewCompanyReports) ...[
              FadeInUp(
                index: step++,
                child: _CompanyPulse(organization: organization),
              ),
              const Gap.lg(),
            ],

            if (me.approvesSomeLeave) ...[
              FadeInUp(
                index: step++,
                child: _ApprovalsBanner(organization: organization, me: me),
              ),
            ],

            FadeInUp(
              index: step++,
              child: SectionHeader(
                title: 'My open tasks',
                actionLabel: 'See all',
                onAction: () => onOpenTab(2),
              ),
            ),
            FadeInUp(
              index: step++,
              child: _OpenTasks(organization: organization, me: me),
            ),
            const Gap.lg(),

            FadeInUp(
              index: step++,
              child: SectionHeader(
                title: 'Announcements',
                actionLabel: 'See all',
                onAction: () => _openFeed(context),
              ),
            ),
            FadeInUp(
              index: step++,
              child: _FeedPreview(organization: organization),
            ),
          ],
        ),
      ),
    );
  }

  void _openFeed(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnnouncementsScreen(organization: organization, me: me),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.me, required this.organization});

  final Employee me;
  final Organization organization;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      me.name.split(' ').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip.role(me.role),
                ],
              ),
            ],
          ),
        ),
        _RoundIcon(
          icon: Icons.campaign_outlined,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  AnnouncementsScreen(organization: organization, me: me),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProfileScreen(organization: organization, me: me),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: Avatar(employee: me, radius: 19),
          ),
        ),
      ],
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);

    return Material(
      color: surfaces.card,
      shape: CircleBorder(side: BorderSide(color: surfaces.border)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            size: 21,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Senior management's view of the whole company at a glance: who is in, who
/// is off, and what is waiting on a decision.
class _CompanyPulse extends StatelessWidget {
  const _CompanyPulse({required this.organization});

  final Organization organization;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);

    return StreamBuilder<List<Employee>>(
      stream: EmployeeService.instance.directory(organization.id),
      builder: (context, peopleSnap) {
        final headcount = (peopleSnap.data ?? const <Employee>[])
            .where((person) => person.active)
            .length;

        return StreamBuilder<List<AttendanceRecord>>(
          stream: AttendanceService.instance.forDate(
            organization.id,
            DateTime.now(),
          ),
          builder: (context, todaySnap) {
            final records = todaySnap.data ?? const <AttendanceRecord>[];
            final present = records.length;
            final late = records.where((r) => r.late).length;

            return AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconBadge(
                        icon: Icons.insights_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 34,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Company today',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              organization.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Gap.md(),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: 'Headcount',
                          value: '$headcount',
                          caption: 'active staff',
                          icon: Icons.groups_rounded,
                        ),
                      ),
                      Expanded(
                        child: StatTile(
                          label: 'Checked in',
                          value: '$present',
                          caption: headcount == 0
                              ? 'nobody yet'
                              : 'of $headcount',
                          color: surfaces.positive,
                          icon: Icons.how_to_reg_rounded,
                        ),
                      ),
                      Expanded(
                        child: StatTile(
                          label: 'Late',
                          value: '$late',
                          caption: late == 1 ? 'person' : 'people',
                          color: late > 0 ? surfaces.caution : null,
                          icon: Icons.running_with_errors_rounded,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Shown only when something is actually waiting on this person.
class _ApprovalsBanner extends StatelessWidget {
  const _ApprovalsBanner({required this.organization, required this.me});

  final Organization organization;
  final Employee me;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);

    return StreamBuilder<List<LeaveRequest>>(
      stream: LeaveService.instance.pendingFor(organization.id, me),
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        if (count == 0) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: AppCard(
            padding: const EdgeInsets.all(14),
            color: surfaces.caution.withValues(alpha: 0.10),
            borderColor: surfaces.caution.withValues(alpha: 0.35),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ApprovalsScreen(organization: organization, me: me),
              ),
            ),
            child: Row(
              children: [
                IconBadge(
                  icon: Icons.how_to_reg_rounded,
                  color: surfaces.caution,
                  size: 40,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$count leave ${count == 1 ? 'request' : 'requests'} '
                        'awaiting you',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        me.approvesAnyLeave
                            ? 'From across the company'
                            : 'From your team',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: surfaces.caution),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OpenTasks extends StatelessWidget {
  const _OpenTasks({required this.organization, required this.me});

  final Organization organization;
  final Employee me;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);

    return StreamBuilder<List<WorkTask>>(
      stream: TaskService.instance.assignedTo(organization.id, me.uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _Muted(
            icon: Icons.error_outline_rounded,
            text: 'Could not load your tasks.',
          );
        }

        final open = (snapshot.data ?? const <WorkTask>[])
            .where((task) => !task.isDone)
            .take(3)
            .toList();

        if (open.isEmpty) {
          return const _Muted(
            icon: Icons.check_circle_outline_rounded,
            text: 'Nothing assigned to you right now.',
          );
        }

        return Column(
          children: [
            for (var i = 0; i < open.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == open.length - 1 ? 0 : 10),
                child: AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 38,
                        decoration: BoxDecoration(
                          color: open[i].isOverdue
                              ? surfaces.negative
                              : Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              open[i].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if (open[i].dueAt != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                open[i].isOverdue
                                    ? 'Overdue · ${Fmt.date(open[i].dueAt!)}'
                                    : 'Due ${Fmt.date(open[i].dueAt!)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: open[i].isOverdue
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: open[i].isOverdue
                                      ? surfaces.negative
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusChip.priority(open[i].priority),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FeedPreview extends StatelessWidget {
  const _FeedPreview({required this.organization});

  final Organization organization;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<List<Announcement>>(
      stream: AnnouncementService.instance.feed(organization.id, limit: 3),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _Muted(
            icon: Icons.error_outline_rounded,
            text: 'Could not load announcements.',
          );
        }

        final items = snapshot.data ?? const <Announcement>[];
        if (items.isEmpty) {
          return const _Muted(
            icon: Icons.campaign_outlined,
            text: 'No announcements yet.',
          );
        }

        return AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) Divider(height: 1, color: surfaces.border),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconBadge(
                        icon: items[i].pinned
                            ? Icons.push_pin_rounded
                            : Icons.campaign_rounded,
                        color: items[i].pinned
                            ? surfaces.caution
                            : scheme.primary,
                        size: 34,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              items[i].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${items[i].authorName} · '
                              '${Fmt.relative(items[i].createdAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
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
      },
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      elevated: false,
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

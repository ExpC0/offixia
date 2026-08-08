import 'package:flutter/material.dart';

import '../format.dart';
import '../models/employee.dart';
import '../models/organization.dart';
import '../models/work_task.dart';
import '../models/team.dart';
import '../services/task_service.dart';
import '../services/team_service.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_chip.dart';
import '../widgets/ui.dart';
import 'task_editor_screen.dart';

/// Work assigned to you, and -- if you assign work -- what you have handed out.
/// Work assigned to me, and -- for anyone who hands work out -- what I gave
/// to others.
///
/// "Anyone who hands work out" is wider than the designation ladder: a team
/// lead can assign inside their own team without holding any rank, so the
/// entry points here are gated on leading a team as well as on the
/// assignTasks authority.
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key, required this.organization, required this.me});

  final Organization organization;
  final Employee me;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Team>>(
      stream: TeamService.instance.all(organization.id),
      builder: (context, snapshot) {
        final led = (snapshot.data ?? const <Team>[])
            .where((team) => team.leadUid == me.uid)
            .toList();
        return _build(context, led);
      },
    );
  }

  Widget _build(BuildContext context, List<Team> ledTeams) {
    final assigns = me.assignsTasks || ledTeams.isNotEmpty;

    return DefaultTabController(
      length: assigns ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tasks'),
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Assigned to me'),
              if (assigns) const Tab(text: 'I assigned'),
            ],
          ),
        ),
        floatingActionButton: assigns
            ? FloatingActionButton.extended(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        TaskEditorScreen(organization: organization, me: me),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('New task'),
              )
            : null,
        body: TabBarView(
          children: [
            _TaskList(
              organization: organization,
              me: me,
              stream: TaskService.instance.assignedTo(organization.id, me.uid),
              emptyTitle: 'No tasks assigned',
              emptyMessage: 'Work assigned to you will appear here.',
            ),
            if (assigns)
              _TaskList(
                organization: organization,
                me: me,
                stream: TaskService.instance.createdBy(organization.id, me.uid),
                emptyTitle: 'You have not assigned anything',
                emptyMessage: 'Tap New task to give someone work.',
              ),
          ],
        ),
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({
    required this.organization,
    required this.me,
    required this.stream,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final Organization organization;
  final Employee me;
  final Stream<List<WorkTask>> stream;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WorkTask>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const ErrorState(message: 'Could not load tasks.');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final tasks = snapshot.data ?? const <WorkTask>[];
        if (tasks.isEmpty) {
          return EmptyState(
            icon: Icons.task_alt_outlined,
            title: emptyTitle,
            message: emptyMessage,
          );
        }

        // Open work first, and within that the most urgent -- a done task is
        // reference material, an urgent one is the reason you opened the tab.
        final sorted = [...tasks]
          ..sort((a, b) {
            if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
            return b.priority.weight.compareTo(a.priority.weight);
          });

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: sorted.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) => _TaskCard(
            organization: organization,
            me: me,
            task: sorted[index],
          ),
        );
      },
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.organization,
    required this.me,
    required this.task,
  });

  final Organization organization;
  final Employee me;
  final WorkTask task;

  bool get _canEdit =>
      task.createdByUid == me.uid || me.managesPeople;
  bool get _canUpdateStatus => task.assigneeUid == me.uid || _canEdit;

  /// Marking done asks first: it removes the task from the board and is the
  /// one status change other people act on.
  Future<void> _changeStatus(BuildContext context, TaskStatus status) async {
    if (status != TaskStatus.done) {
      await _setStatus(context, status);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mark as done?'),
        content: Text(
          'This closes "${task.title}" and takes it off the active board. '
          'Reopening it afterwards takes a second confirmation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Mark done'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await _setStatus(context, TaskStatus.done);
  }

  /// Undoing a completion. Deliberately awkward -- somebody may already have
  /// acted on this being finished.
  Future<void> _reopen(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reopen this task?'),
        content: Text(
          '"${task.title}" was completed'
          '${task.completedAt == null ? '' : ' ${Fmt.relative(task.completedAt)}'}'
          '. Reopening puts it back on the board, and anyone who saw it '
          'finished will not be told.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Leave it done'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppSurfaces.of(dialogContext).caution,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await _setStatus(context, TaskStatus.todo);
  }

  Future<void> _setStatus(BuildContext context, TaskStatus status) async {
    final messenger = ScaffoldMessenger.of(context);
    final negative = AppSurfaces.of(context).negative;
    try {
      await TaskService.instance.updateStatus(
        orgId: organization.id,
        task: task,
        status: status,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: negative,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _canEdit
            ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TaskEditorScreen(
                    organization: organization,
                    me: me,
                    existing: task,
                  ),
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        decoration: task.isDone
                            ? TextDecoration.lineThrough
                            : null,
                        color: task.isDone ? scheme.onSurfaceVariant : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip.priority(task.priority),
                ],
              ),
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  task.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusChip.task(task.status),
                  Text(
                    task.assigneeUid == me.uid
                        ? 'Assigned to you'
                        : task.assigneeName,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (task.dueAt != null)
                    Text(
                      task.isOverdue
                          ? 'Overdue · ${Fmt.date(task.dueAt!)}'
                          : 'Due ${Fmt.date(task.dueAt!)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: task.isOverdue
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: task.isOverdue
                            ? AppSurfaces.of(context).negative
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              if (_canUpdateStatus) ...[
                const SizedBox(height: 12),
                // Finished work leaves the board. Showing "To do" and "Doing"
                // next to a completed task invites an accidental tap that
                // quietly undoes a completion somebody else is relying on, so
                // done collapses to a statement plus a guarded way back.
                if (task.isDone)
                  Row(
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 17,
                        color: AppSurfaces.of(context).positive,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        task.completedAt == null
                            ? 'Completed'
                            : 'Completed ${Fmt.relative(task.completedAt)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppSurfaces.of(context).positive,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _reopen(context),
                        child: const Text('Reopen'),
                      ),
                    ],
                  )
                else
                  SegmentedButton<TaskStatus>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: TaskStatus.todo,
                        label: Text('To do'),
                      ),
                      ButtonSegment(
                        value: TaskStatus.inProgress,
                        label: Text('Doing'),
                      ),
                      ButtonSegment(
                        value: TaskStatus.done,
                        label: Text('Done'),
                      ),
                    ],
                    selected: {task.status},
                    onSelectionChanged: (selection) =>
                        _changeStatus(context, selection.first),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

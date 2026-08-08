import 'package:flutter/material.dart';

import '../format.dart';
import '../models/employee.dart';
import '../models/organization.dart';
import '../models/team.dart';
import '../models/work_task.dart';
import '../services/employee_service.dart';
import '../services/task_service.dart';
import '../theme.dart';
import '../widgets/avatar.dart';

/// Create or edit a task. One screen for both, because the fields are the same
/// and the only difference is whether there is something to delete.
class TaskEditorScreen extends StatefulWidget {
  const TaskEditorScreen({
    super.key,
    required this.organization,
    required this.me,
    this.existing,
    this.ledTeams = const [],
  });

  final Organization organization;
  final Employee me;
  final WorkTask? existing;

  /// Teams this person leads. Someone with no assignTasks authority may still
  /// hand work to members of these, and only to them.
  final List<Team> ledTeams;

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;

  TaskPriority _priority = TaskPriority.normal;
  DateTime? _dueAt;
  Employee? _assignee;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  /// The people this person may assign to, or null for anyone.
  ///
  /// Somebody who holds assignTasks can give work to the whole company. A team
  /// lead who does not can only reach their own members, so the picker is
  /// narrowed to exactly what the security rules will accept -- offering more
  /// would just produce a permission error at save time.
  Set<String>? get _restrictedTo {
    if (widget.me.assignsTasks) return null;
    if (widget.ledTeams.isEmpty) return null;
    return {
      for (final team in widget.ledTeams) ...team.memberUids,
    }..remove(widget.me.uid);
  }

  /// The team to record on the task, so the rules can verify the assignment.
  String? _teamFor(Employee assignee) {
    if (widget.me.assignsTasks) return null;
    for (final team in widget.ledTeams) {
      if (team.includes(assignee.uid)) return team.id;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    _priority = existing?.priority ?? TaskPriority.normal;
    _dueAt = existing?.dueAt;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _dueAt = picked);
  }

  Future<void> _save() async {
    final assignee = _assignee;
    if (assignee == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pick who this is for.')));
      return;
    }

    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final existing = widget.existing;
      if (existing == null) {
        await TaskService.instance.create(
          orgId: widget.organization.id,
          createdBy: widget.me,
          assignee: assignee,
          title: _titleController.text,
          description: _descriptionController.text,
          priority: _priority,
          dueAt: _dueAt,
          teamId: _teamFor(assignee),
        );
      } else {
        await TaskService.instance.edit(
          orgId: widget.organization.id,
          task: existing,
          title: _titleController.text,
          description: _descriptionController.text,
          priority: _priority,
          assignee: assignee,
          dueAt: _dueAt,
        );
      }
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Task updated.' : 'Task assigned.')),
      );
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

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this task?'),
        content: const Text('It will be removed for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.negative),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await TaskService.instance.delete(
        orgId: widget.organization.id,
        task: existing,
      );
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Task deleted.')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.negative,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit task' : 'New task'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _titleController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'What needs doing',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _descriptionController,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Details (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Assign to',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _AssigneePicker(
            organization: widget.organization,
            initialUid: widget.existing?.assigneeUid,
            allowedUids: _restrictedTo,
            onChanged: (employee) => setState(() => _assignee = employee),
          ),
          if (_restrictedTo != null) ...[
            const SizedBox(height: 8),
            Text(
              'You lead '
              '${widget.ledTeams.map((team) => team.name).join(', ')}, so you '
              'can assign work to those members.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 22),
          const Text(
            'Priority',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final priority in TaskPriority.values)
                ChoiceChip(
                  label: Text(priority.label),
                  selected: _priority == priority,
                  onSelected: (_) => setState(() => _priority = priority),
                ),
            ],
          ),
          const SizedBox(height: 18),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: const Text('Due date'),
            subtitle: Text(_dueAt == null ? 'None' : Fmt.fullDate(_dueAt!)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_dueAt != null)
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _dueAt = null),
                  ),
                TextButton(onPressed: _pickDue, child: const Text('Set')),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(
              _busy ? 'Saving...' : (_isEdit ? 'Save changes' : 'Assign task'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A horizontal strip of teammates. Small orgs are the target here, so showing
/// everyone beats a search field nobody needs.
class _AssigneePicker extends StatefulWidget {
  const _AssigneePicker({
    required this.organization,
    required this.onChanged,
    required this.allowedUids,
    this.initialUid,
  });

  final Organization organization;
  final String? initialUid;
  final ValueChanged<Employee> onChanged;

  /// Null means anyone in the company. A set means a team lead is assigning,
  /// and the rules will only accept somebody inside their team.
  final Set<String>? allowedUids;

  @override
  State<_AssigneePicker> createState() => _AssigneePickerState();
}

class _AssigneePickerState extends State<_AssigneePicker> {
  String? _selectedUid;
  bool _appliedInitial = false;

  @override
  void initState() {
    super.initState();
    _selectedUid = widget.initialUid;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Employee>>(
      stream: EmployeeService.instance.directory(widget.organization.id),
      builder: (context, snapshot) {
        final allowed = widget.allowedUids;
        final people = (snapshot.data ?? const <Employee>[])
            .where(
              (employee) =>
                  employee.active &&
                  (allowed == null || allowed.contains(employee.uid)),
            )
            .toList();

        if (people.isEmpty) {
          return const SizedBox(
            height: 84,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        // Report the pre-selected employee upward once the directory has
        // actually loaded, so editing a task does not require re-picking the
        // person who is already on it.
        if (!_appliedInitial && _selectedUid != null) {
          final match = people.where((p) => p.uid == _selectedUid).firstOrNull;
          if (match != null) {
            _appliedInitial = true;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => widget.onChanged(match),
            );
          }
        }

        return SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: people.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final person = people[index];
              final selected = person.uid == _selectedUid;

              return GestureDetector(
                onTap: () {
                  setState(() => _selectedUid = person.uid);
                  widget.onChanged(person);
                },
                child: SizedBox(
                  width: 68,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: Avatar(employee: person, radius: 24),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        person.name.split(' ').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

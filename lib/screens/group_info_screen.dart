import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../models/employee.dart';
import '../models/organization.dart';
import '../services/chat_service.dart';
import '../services/employee_service.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/ui.dart';

/// Everything about a group: who is in it, and what you can do to it.
///
/// The split of authority follows the security rules exactly. The creator
/// owns the group -- its name, its roster, and whether it exists at all.
/// Everyone else can read it and leave it.
class GroupInfoScreen extends StatelessWidget {
  const GroupInfoScreen({
    super.key,
    required this.organization,
    required this.me,
    required this.chatId,
  });

  final Organization organization;
  final Employee me;
  final String chatId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ChatGroup?>(
      stream: ChatService.instance.watch(organization.id, chatId),
      builder: (context, snapshot) {
        final chat = snapshot.data;
        if (chat == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Group info')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return _GroupInfoBody(
          organization: organization,
          me: me,
          chat: chat,
        );
      },
    );
  }
}

class _GroupInfoBody extends StatefulWidget {
  const _GroupInfoBody({
    required this.organization,
    required this.me,
    required this.chat,
  });

  final Organization organization;
  final Employee me;
  final ChatGroup chat;

  @override
  State<_GroupInfoBody> createState() => _GroupInfoBodyState();
}

class _GroupInfoBodyState extends State<_GroupInfoBody> {
  bool _busy = false;

  bool get _isCreator => widget.chat.createdByUid == widget.me.uid;

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

  Future<void> _rename() async {
    final controller = TextEditingController(text: widget.chat.name);
    final descriptionController = TextEditingController(
      text: widget.chat.description,
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Group name'),
            ),
            const Gap.sm(),
            TextField(
              controller: descriptionController,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;

    await _run(
      () => ChatService.instance.rename(
        orgId: widget.organization.id,
        chatId: widget.chat.id,
        name: controller.text,
        description: descriptionController.text,
      ),
      'Group updated.',
    );
  }

  Future<void> _addPeople() async {
    final everyone = await EmployeeService.instance
        .directory(widget.organization.id)
        .first;
    if (!mounted) return;

    final candidates = everyone
        .where(
          (person) =>
              person.active && !widget.chat.memberUids.contains(person.uid),
        )
        .toList();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Everyone is already in this group.')),
      );
      return;
    }

    final picked = <String>{};
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Text(
                      'Add people',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Text('${picked.length} selected'),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (context, index) {
                    final person = candidates[index];
                    return CheckboxListTile(
                      value: picked.contains(person.uid),
                      onChanged: (value) => setSheetState(() {
                        if (value == true) {
                          picked.add(person.uid);
                        } else {
                          picked.remove(person.uid);
                        }
                      }),
                      secondary: Avatar(employee: person),
                      title: Text(person.name),
                      subtitle: Text(person.subtitle),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: picked.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(true),
                    child: const Text('Add to group'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    await _run(
      () => ChatService.instance.addMembers(
        orgId: widget.organization.id,
        chatId: widget.chat.id,
        uids: picked.toList(),
      ),
      picked.length == 1 ? 'Added 1 person.' : 'Added ${picked.length} people.',
    );
  }

  Future<void> _removeMember(Employee person) async {
    final confirmed = await _confirm(
      title: 'Remove ${person.name.split(' ').first}?',
      body: 'They will lose access to this group and its messages.',
      action: 'Remove',
    );
    if (confirmed != true || !mounted) return;

    await _run(
      () => ChatService.instance.removeMember(
        orgId: widget.organization.id,
        chatId: widget.chat.id,
        uid: person.uid,
      ),
      '${person.name} removed.',
    );
  }

  Future<void> _leave() async {
    final confirmed = await _confirm(
      title: 'Leave this group?',
      body: _isCreator
          ? 'You created this group. Leaving does not delete it, but nobody '
                'else will be able to rename it or manage who is in it.'
          : 'You will stop receiving its messages. Someone in the group can '
                'add you back.',
      action: 'Leave',
    );
    if (confirmed != true || !mounted) return;

    final navigator = Navigator.of(context);
    await _run(
      () => ChatService.instance.leave(
        orgId: widget.organization.id,
        chatId: widget.chat.id,
        uid: widget.me.uid,
      ),
      'You left the group.',
    );
    // Back past the thread as well -- it is no longer readable.
    if (mounted) navigator.popUntil((route) => route.isFirst);
  }

  Future<void> _delete() async {
    final confirmed = await _confirm(
      title: 'Delete this group?',
      body: 'The group and every message in it are removed for everyone. '
          'This cannot be undone.',
      action: 'Delete',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    final navigator = Navigator.of(context);
    await _run(
      () => ChatService.instance.deleteGroup(
        orgId: widget.organization.id,
        chatId: widget.chat.id,
      ),
      'Group deleted.',
    );
    if (mounted) navigator.popUntil((route) => route.isFirst);
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: AppSurfaces.of(context).negative,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final surfaces = AppSurfaces.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group info'),
        actions: [
          if (_isCreator)
            IconButton(
              tooltip: 'Edit group',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _busy ? null : _rename,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Center(
            child: Column(
              children: [
                IconBadge(
                  icon: Icons.groups_rounded,
                  color: scheme.primary,
                  size: 72,
                ),
                const Gap.md(),
                Text(
                  chat.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '${chat.memberUids.length} '
                  '${chat.memberUids.length == 1 ? 'member' : 'members'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (chat.description.isNotEmpty) ...[
                  const Gap.sm(),
                  Text(
                    chat.description,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
          const Gap.lg(),
          SectionHeader(
            title: 'Members',
            actionLabel: _isCreator ? 'Add' : null,
            onAction: _busy ? null : _addPeople,
          ),
          _MemberList(
            organization: widget.organization,
            chat: chat,
            me: widget.me,
            canRemove: _isCreator,
            onRemove: _busy ? null : _removeMember,
          ),
          const Gap.lg(),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.logout_rounded, color: surfaces.caution),
                  title: const Text('Leave group'),
                  subtitle: const Text('You can be added back later'),
                  onTap: _busy ? null : _leave,
                ),
                if (_isCreator) ...[
                  Divider(height: 1, color: surfaces.border),
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: surfaces.negative,
                    ),
                    title: Text(
                      'Delete group',
                      style: TextStyle(color: surfaces.negative),
                    ),
                    subtitle: const Text('Removes it for everyone'),
                    onTap: _busy ? null : _delete,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberList extends StatelessWidget {
  const _MemberList({
    required this.organization,
    required this.chat,
    required this.me,
    required this.canRemove,
    required this.onRemove,
  });

  final Organization organization;
  final ChatGroup chat;
  final Employee me;
  final bool canRemove;
  final ValueChanged<Employee>? onRemove;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);

    return StreamBuilder<List<Employee>>(
      stream: EmployeeService.instance.directory(organization.id),
      builder: (context, snapshot) {
        final everyone = snapshot.data ?? const <Employee>[];
        final members = everyone
            .where((person) => chat.memberUids.contains(person.uid))
            .toList();

        if (members.isEmpty) {
          return const AppCard(
            child: Text('Loading members...'),
          );
        }

        return AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < members.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 68, color: surfaces.border),
                ListTile(
                  leading: Avatar(employee: members[i]),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          members[i].name,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (members[i].uid == me.uid)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Text('(you)', style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    members[i].uid == chat.createdByUid
                        ? 'Created this group'
                        : members[i].subtitle,
                  ),
                  trailing: (canRemove && members[i].uid != me.uid)
                      ? IconButton(
                          tooltip: 'Remove',
                          icon: Icon(
                            Icons.remove_circle_outline_rounded,
                            color: surfaces.negative,
                          ),
                          onPressed: onRemove == null
                              ? null
                              : () => onRemove!(members[i]),
                        )
                      : null,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

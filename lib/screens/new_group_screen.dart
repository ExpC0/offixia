import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../models/organization.dart';
import '../services/chat_service.dart';
import '../services/employee_service.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/empty_state.dart';
import '../widgets/ui.dart';
import 'chat_thread_screen.dart';

class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({
    super.key,
    required this.organization,
    required this.me,
  });
  final Organization organization;
  final Employee me;

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _selected = <String>{};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create(List<Employee> people) async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final negative = AppSurfaces.of(context).negative;
    try {
      final id = await ChatService.instance.createGroup(
        orgId: widget.organization.id,
        creator: widget.me,
        name: _name.text,
        description: _description.text,
        members: people
            .where((person) => _selected.contains(person.uid))
            .toList(),
      );
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ChatThreadScreen(
            organization: widget.organization,
            me: widget.me,
            chatId: id,
            fallbackTitle: _name.text.trim(),
          ),
        ),
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
    return Scaffold(
      appBar: AppBar(title: const Text('New group')),
      body: StreamBuilder<List<Employee>>(
        stream: EmployeeService.instance.directory(widget.organization.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ErrorState(message: 'Could not load the directory.');
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final people = (snapshot.data ?? const <Employee>[])
              .where((person) => person.uid != widget.me.uid && person.active)
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              AppCard(
                child: Column(
                  children: [
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Group name',
                      ),
                    ),
                    const Gap.sm(),
                    TextField(
                      controller: _description,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'Optional',
                      ),
                    ),
                  ],
                ),
              ),
              const Gap.lg(),
              SectionHeader(title: 'Members (${_selected.length})'),
              AppCard(
                padding: EdgeInsets.zero,
                child: people.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No other active team members yet.'),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < people.length; i++) ...[
                            if (i > 0) const Divider(height: 1, indent: 68),
                            CheckboxListTile(
                              value: _selected.contains(people[i].uid),
                              secondary: Avatar(employee: people[i]),
                              title: Text(people[i].name),
                              subtitle: Text(people[i].subtitle),
                              onChanged: _busy
                                  ? null
                                  : (selected) => setState(() {
                                      if (selected == true) {
                                        _selected.add(people[i].uid);
                                      } else {
                                        _selected.remove(people[i].uid);
                                      }
                                    }),
                            ),
                          ],
                        ],
                      ),
              ),
              const Gap.lg(),
              FilledButton.icon(
                onPressed: _busy ? null : () => _create(people),
                icon: const Icon(Icons.group_add_outlined),
                label: Text(_busy ? 'Creating…' : 'Create group'),
              ),
            ],
          );
        },
      ),
    );
  }
}

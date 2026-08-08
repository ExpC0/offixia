import 'package:flutter/material.dart';

import '../format.dart';
import '../models/chat.dart';
import '../models/employee.dart';
import '../models/organization.dart';
import '../services/chat_alerts_service.dart';
import '../services/chat_service.dart';
import '../services/employee_service.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/ui.dart';
import 'chat_thread_screen.dart';
import 'new_group_screen.dart';

/// Conversations the signed-in person belongs to.
///
/// Stateful purely to hold the streams. `snapshots()` returns a *new* stream
/// on every call, so building one inside `build()` makes StreamBuilder tear
/// down and resubscribe on each rebuild -- which drops the list back to its
/// loading spinner every time anything changes. Creating them once in
/// [initState] is what stops the list flickering.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key, required this.organization, required this.me});

  final Organization organization;
  final Employee me;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  late final Stream<List<Employee>> _people;
  late final Stream<List<ChatGroup>> _chats;

  @override
  void initState() {
    super.initState();
    _people = EmployeeService.instance.directory(widget.organization.id);
    _chats = ChatService.instance.myChats(
      widget.organization.id,
      widget.me.uid,
    );
  }

  void _openNewGroup() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NewGroupScreen(
          organization: widget.organization,
          me: widget.me,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            tooltip: 'New group',
            icon: const Icon(Icons.group_add_outlined),
            onPressed: _openNewGroup,
          ),
        ],
      ),
      body: StreamBuilder<List<Employee>>(
        stream: _people,
        builder: (context, peopleSnapshot) {
          final people = {
            for (final person in peopleSnapshot.data ?? const <Employee>[])
              person.uid: person,
          };

          return StreamBuilder<List<ChatGroup>>(
            stream: _chats,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const ErrorState(message: 'Could not load chats.');
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final chats = snapshot.data ?? const <ChatGroup>[];
              if (chats.isEmpty) {
                return EmptyState(
                  icon: Icons.forum_outlined,
                  title: 'No conversations yet',
                  message:
                      'Create a group or open a teammate to start chatting.',
                  action: FilledButton.icon(
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('New group'),
                    onPressed: _openNewGroup,
                  ),
                );
              }

              // Rebuilt on the unread set alone, so marking one thread read
              // repaints the rows without touching either Firestore stream.
              return ValueListenableBuilder<Set<String>>(
                valueListenable: ChatAlertsService.instance.unread,
                builder: (context, unread, _) => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  itemCount: chats.length,
                  separatorBuilder: (_, _) => const Gap.sm(),
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    final other = chat.isDirect
                        ? people[chat.memberUids
                              .where((uid) => uid != widget.me.uid)
                              .firstOrNull]
                        : null;
                    final title = chat.isDirect
                        ? (other?.name ?? 'Direct message')
                        : chat.name;

                    return _ChatRow(
                      organization: widget.organization,
                      me: widget.me,
                      chat: chat,
                      title: title,
                      isUnread: unread.contains(chat.id),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.organization,
    required this.me,
    required this.chat,
    required this.title,
    required this.isUnread,
  });

  final Organization organization;
  final Employee me;
  final ChatGroup chat;
  final String title;
  final bool isUnread;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaces = AppSurfaces.of(context);

    final preview = chat.lastMessage.isEmpty
        ? (chat.description.isEmpty ? 'No messages yet' : chat.description)
        : '${chat.lastSenderName.isEmpty ? '' : '${chat.lastSenderName}: '}'
              '${chat.lastMessage}';

    return AppCard(
      padding: EdgeInsets.zero,
      // Unread rows get a tinted surface and a brand-coloured border, so the
      // state is legible without relying on weight alone.
      color: isUnread ? scheme.primary.withValues(alpha: 0.07) : null,
      borderColor: isUnread
          ? scheme.primary.withValues(alpha: 0.35)
          : surfaces.border,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatThreadScreen(
            organization: organization,
            me: me,
            chatId: chat.id,
            fallbackTitle: title,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            IconBadge(
              icon: chat.isDirect
                  ? Icons.person_outline_rounded
                  : Icons.groups_outlined,
              color: chat.isDirect ? scheme.secondary : scheme.primary,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isUnread
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isUnread
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isUnread
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  Fmt.relative(chat.lastMessageAt),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isUnread ? FontWeight.w700 : FontWeight.w400,
                    color: isUnread
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                // A filled dot for unread, an empty slot of the same size for
                // read, so rows do not shift as their state changes.
                SizedBox(
                  height: 10,
                  width: 10,
                  child: isUnread
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

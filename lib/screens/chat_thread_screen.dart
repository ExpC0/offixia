import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models/chat.dart';
import '../models/call.dart';
import '../models/employee.dart';
import '../models/organization.dart';
import '../services/chat_alerts_service.dart';
import '../services/chat_service.dart';
import '../services/group_calls.dart';
import '../services/calls.dart';
import '../services/employee_service.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/empty_state.dart';
import 'employee_detail_screen.dart';
import 'group_info_screen.dart';

/// A conversation.
///
/// Laid out the way a messaging app is expected to be: newest at the bottom,
/// consecutive messages from one person grouped under a single name and
/// avatar, a date separator whenever the day changes, and the time only on the
/// last message of a run. The grouping is what stops a long exchange reading
/// as a wall of repeated headers.
class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.organization,
    required this.me,
    required this.chatId,
    required this.fallbackTitle,
  });

  final Organization organization;
  final Employee me;
  final String chatId;
  final String fallbackTitle;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  // Created once. `snapshots()` hands back a new stream on every call, so
  // building these inside `build()` would resubscribe on each rebuild -- and
  // the chat document rebuilds on every message, since sending updates its
  // preview.
  late final Stream<ChatGroup?> _chat;
  late final Stream<List<ChatMessage>> _messages;
  late final Stream<List<Employee>> _people;

  @override
  void initState() {
    super.initState();
    _chat = ChatService.instance.watch(widget.organization.id, widget.chatId);
    _messages = ChatService.instance.messages(
      widget.organization.id,
      widget.chatId,
    );
    _people = EmployeeService.instance.directory(widget.organization.id);

    // Tells the alert service to stop notifying about a thread being read.
    ChatAlertsService.instance.setOpenChat(widget.chatId);
  }

  @override
  void dispose() {
    ChatAlertsService.instance.setOpenChat(null);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Fires the write without waiting on the server.
  ///
  /// Firestore applies a write locally first and emits it on the snapshot
  /// stream immediately, marked pending until acknowledged. Awaiting the
  /// commit before re-enabling the composer stalled every message for a full
  /// round trip even though it was already on screen.
  void _send() {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    _controller.clear();

    final messenger = ScaffoldMessenger.of(context);
    final negative = AppSurfaces.of(context).negative;

    ChatService.instance
        .send(
          orgId: widget.organization.id,
          chatId: widget.chatId,
          sender: widget.me,
          text: body,
        )
        .catchError((Object error) {
          if (!mounted) return;
          // Hand the text back so a failed send is never silently lost.
          _controller.text = body;
          messenger.showSnackBar(
            SnackBar(
              content: Text(error.toString().replaceFirst('Exception: ', '')),
              backgroundColor: negative,
            ),
          );
        });
  }

  Future<void> _openProfile(Employee person) async {
    if (person.uid == widget.me.uid) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmployeeDetailScreen(
          organization: widget.organization,
          me: widget.me,
          person: person,
        ),
      ),
    );
  }

  Future<void> _messageActions(ChatMessage message) async {
    final mine = message.senderUid == widget.me.uid;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy text'),
              onTap: () => Navigator.of(sheetContext).pop('copy'),
            ),
            if (mine)
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: AppSurfaces.of(sheetContext).negative,
                ),
                title: Text(
                  'Delete for everyone',
                  style: TextStyle(
                    color: AppSurfaces.of(sheetContext).negative,
                  ),
                ),
                subtitle: const Text('Removes it from the conversation'),
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
          ],
        ),
      ),
    );

    if (action == null || !mounted) return;

    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.text));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Copied.')));
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final negative = AppSurfaces.of(context).negative;
    try {
      await ChatService.instance.deleteMessage(
        orgId: widget.organization.id,
        chatId: widget.chatId,
        messageId: message.id,
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: negative,
        ),
      );
    }
  }

  Future<void> _toggleBlock(ChatGroup chat, Employee? other) async {
    final blocking = !chat.isBlocked;

    if (blocking) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            'Block ${other?.name.split(' ').first ?? 'this person'}?',
          ),
          content: const Text(
            'Neither of you can send messages in this conversation until it '
            'is unblocked. The history stays.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppSurfaces.of(dialogContext).negative,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final negative = AppSurfaces.of(context).negative;
    try {
      await ChatService.instance.setBlocked(
        orgId: widget.organization.id,
        chatId: widget.chatId,
        uid: widget.me.uid,
        blocked: blocking,
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: negative,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ChatGroup?>(
      stream: _chat,
      builder: (context, chatSnapshot) {
        final chat = chatSnapshot.data;

        return StreamBuilder<List<Employee>>(
          stream: _people,
          builder: (context, peopleSnapshot) {
            final byUid = {
              for (final person in peopleSnapshot.data ?? const <Employee>[])
                person.uid: person,
            };

            final other = chat?.isDirect == true
                ? byUid[chat!.otherMember(widget.me.uid)]
                : null;

            final title = chat == null
                ? widget.fallbackTitle
                : (chat.isDirect
                      ? (other?.name ?? widget.fallbackTitle)
                      : chat.name);

            return Scaffold(
              appBar: _buildAppBar(context, chat, other, title, byUid),
              body: Column(
                children: [
                  Expanded(child: _buildMessages(byUid, chat)),
                  if (chat != null && chat.isBlocked)
                    _BlockedBar(
                      blockedByMe: chat.blockedByMe(widget.me.uid),
                      onUnblock: () => _toggleBlock(chat, other),
                    )
                  else
                    _Composer(
                      controller: _controller,
                      focusNode: _focus,
                      onSend: _send,
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ChatGroup? chat,
    Employee? other,
    String title,
    Map<String, Employee> byUid,
  ) {
    final scheme = Theme.of(context).colorScheme;

    return AppBar(
      titleSpacing: 0,
      title: InkWell(
        // The header is the shortest route to "who is this?", so it opens the
        // profile for a direct thread and the roster for a group.
        onTap: () {
          if (other != null) {
            _openProfile(other);
          } else if (chat != null && !chat.isDirect) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => GroupInfoScreen(
                  organization: widget.organization,
                  me: widget.me,
                  chatId: widget.chatId,
                ),
              ),
            );
          }
        },
        child: Row(
          children: [
            if (other != null)
              Avatar(employee: other, radius: 17)
            else
              CircleAvatar(
                radius: 17,
                backgroundColor: scheme.primary.withValues(alpha: 0.15),
                child: Icon(
                  Icons.groups_rounded,
                  size: 19,
                  color: scheme.primary,
                ),
              ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    other != null
                        ? other.subtitle
                        : '${chat?.memberUids.length ?? 0} members',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (chat != null &&
            chat.isDirect &&
            other != null &&
            !chat.isBlocked) ...[
          IconButton(
            tooltip: 'Audio call',
            icon: const Icon(Icons.call_rounded),
            onPressed: () => Calls.start(
              context: context,
              organization: widget.organization,
              me: widget.me,
              other: other,
              kind: CallKind.audio,
            ),
          ),
          IconButton(
            tooltip: 'Video call',
            icon: const Icon(Icons.videocam_rounded),
            onPressed: () => Calls.start(
              context: context,
              organization: widget.organization,
              me: widget.me,
              other: other,
              kind: CallKind.video,
            ),
          ),
        ],
        if (chat != null && !chat.isDirect) ...[
          IconButton(
            tooltip: 'Group audio call',
            icon: const Icon(Icons.call_rounded),
            onPressed: () => GroupCalls.start(
              context: context,
              organization: widget.organization,
              me: widget.me,
              chat: chat,
              kind: CallKind.audio,
              people: byUid,
            ),
          ),
          IconButton(
            tooltip: 'Group video call',
            icon: const Icon(Icons.videocam_rounded),
            onPressed: () => GroupCalls.start(
              context: context,
              organization: widget.organization,
              me: widget.me,
              chat: chat,
              kind: CallKind.video,
              people: byUid,
            ),
          ),
        ],
        if (chat != null && chat.isDirect)
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'profile' && other != null) _openProfile(other);
              if (value == 'block') _toggleBlock(chat, other);
            },
            itemBuilder: (context) => [
              if (other != null)
                const PopupMenuItem(
                  value: 'profile',
                  child: Text('View profile'),
                ),
              PopupMenuItem(
                value: 'block',
                child: Text(chat.isBlocked ? 'Unblock' : 'Block'),
              ),
            ],
          )
        else if (chat != null)
          IconButton(
            tooltip: 'Group info',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => GroupInfoScreen(
                  organization: widget.organization,
                  me: widget.me,
                  chatId: widget.chatId,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessages(Map<String, Employee> byUid, ChatGroup? chat) {
    return StreamBuilder<List<ChatMessage>>(
      stream: _messages,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const ErrorState(message: 'Could not load messages.');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final messages = snapshot.data ?? const <ChatMessage>[];
        if (messages.isEmpty) {
          return EmptyState(
            icon: Icons.chat_bubble_outline,
            title: 'No messages yet',
            message: chat?.isDirect == true
                ? 'Say hello. Only the two of you can read this.'
                : 'Everyone in this group can read what is sent here.',
          );
        }

        // The list is newest-first and rendered reversed, so "the message
        // after this one in the list" is actually the one *above* it on
        // screen. Grouping compares against that.
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final older = index + 1 < messages.length
                ? messages[index + 1]
                : null;
            final newer = index > 0 ? messages[index - 1] : null;

            final mine = message.senderUid == widget.me.uid;
            final startsRun =
                older == null || older.senderUid != message.senderUid;
            final endsRun =
                newer == null || newer.senderUid != message.senderUid;

            final showDate =
                older == null || !_sameDay(older.sentAt, message.sentAt);

            return Column(
              children: [
                if (showDate) _DateChip(when: message.sentAt),
                _MessageBubble(
                  message: message,
                  mine: mine,
                  isGroup: chat?.isDirect == false,
                  showName: startsRun && !mine,
                  showTail: endsRun,
                  sender: byUid[message.senderUid],
                  onAvatarTap: () {
                    final person = byUid[message.senderUid];
                    if (person != null) _openProfile(person);
                  },
                  onLongPress: () => _messageActions(message),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

/// The "Today" / "Yesterday" / date marker between days.
class _DateChip extends StatelessWidget {
  const _DateChip({required this.when});

  final DateTime? when;

  @override
  Widget build(BuildContext context) {
    if (when == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(when!.year, when!.month, when!.day);
    final difference = today.difference(that).inDays;

    final label = switch (difference) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => Fmt.fullDate(when!),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.isGroup,
    required this.showName,
    required this.showTail,
    required this.sender,
    required this.onAvatarTap,
    required this.onLongPress,
  });

  final ChatMessage message;
  final bool mine;
  final bool isGroup;
  final bool showName;
  final bool showTail;
  final Employee? sender;
  final VoidCallback onAvatarTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaces = AppSurfaces.of(context);

    // Only the last bubble of a run gets a tail, so a burst of messages reads
    // as one block rather than a stack of separate cards.
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(mine || !showTail ? 16 : 4),
      bottomRight: Radius.circular(mine && showTail ? 4 : 16),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: showTail ? 8 : 2),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // The avatar slot is reserved even when empty, so grouped messages
          // stay aligned with the one that carries the face.
          if (!mine && isGroup)
            SizedBox(
              width: 34,
              child: showTail && sender != null
                  ? GestureDetector(
                      onTap: onAvatarTap,
                      child: Avatar(employee: sender!, radius: 13),
                    )
                  : null,
            ),
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 300),
                padding: const EdgeInsets.fromLTRB(13, 9, 13, 7),
                decoration: BoxDecoration(
                  color: mine ? scheme.primaryContainer : surfaces.card,
                  border: Border.all(
                    color: mine
                        ? scheme.primary.withValues(alpha: 0.22)
                        : surfaces.border,
                  ),
                  borderRadius: radius,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showName && isGroup)
                      GestureDetector(
                        onTap: onAvatarTap,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            message.senderName,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ),
                    Text(
                      message.text,
                      style: const TextStyle(fontSize: 14.5, height: 1.35),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.pending
                              ? 'Sending'
                              : Fmt.time(message.sentAt),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (mine) ...[
                          const SizedBox(width: 4),
                          Icon(
                            message.pending
                                ? Icons.schedule_rounded
                                : Icons.done_all_rounded,
                            size: 12,
                            color: message.pending
                                ? scheme.onSurfaceVariant
                                : scheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Replaces the composer while a conversation is blocked.
class _BlockedBar extends StatelessWidget {
  const _BlockedBar({required this.blockedByMe, required this.onUnblock});

  final bool blockedByMe;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: surfaces.card,
          border: Border(top: BorderSide(color: surfaces.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.block_rounded, size: 18, color: surfaces.negative),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    blockedByMe
                        ? 'You blocked this conversation.'
                        : 'This conversation has been blocked.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: surfaces.negative,
                    ),
                  ),
                ),
              ],
            ),
            if (blockedByMe) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onUnblock,
                  child: const Text('Unblock'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        decoration: BoxDecoration(
          color: surfaces.card,
          border: Border(top: BorderSide(color: surfaces.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(hintText: 'Message'),
              ),
            ),
            const SizedBox(width: 8),
            // No busy state: the message is already on screen marked
            // "Sending", so blocking the next one would only get in the way.
            IconButton.filled(
              tooltip: 'Send',
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

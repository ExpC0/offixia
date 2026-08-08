import 'package:flutter/material.dart';

import '../format.dart';
import '../models/announcement.dart';
import '../models/employee.dart';
import '../models/organization.dart';
import '../services/announcement_service.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/ui.dart';

/// The company feed. Everyone reads it; HR and the owner can post and pin.
class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({
    super.key,
    required this.organization,
    required this.me,
  });

  final Organization organization;
  final Employee me;

  @override
  Widget build(BuildContext context) {
    final canPost = me.postsAnnouncements;

    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      floatingActionButton: canPost
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      _ComposeScreen(organization: organization, me: me),
                ),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Post'),
            )
          : null,
      body: StreamBuilder<List<Announcement>>(
        stream: AnnouncementService.instance.feed(organization.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ErrorState(message: 'Could not load the feed.');
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data ?? const <Announcement>[];
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.campaign_outlined,
              title: 'Nothing announced yet',
              message: canPost
                  ? 'Tap Post to tell the team something.'
                  : 'Company news will show up here.',
            );
          }

          return ListView.separated(
            padding: EdgeInsets.fromLTRB(16, 12, 16, canPost ? 96 : 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _AnnouncementCard(
              organization: organization,
              me: me,
              announcement: items[index],
            ),
          );
        },
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.organization,
    required this.me,
    required this.announcement,
  });

  final Organization organization;
  final Employee me;
  final Announcement announcement;

  /// HR and the owner can moderate anything; anyone else only their own post.
  bool get _canManage =>
      me.postsAnnouncements || announcement.authorUid == me.uid;

  Future<void> _delete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final negative = AppSurfaces.of(context).negative;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this announcement?'),
        content: const Text('It will disappear for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppSurfaces.of(context).negative,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await AnnouncementService.instance.delete(
        orgId: organization.id,
        announcement: announcement,
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (announcement.pinned)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 2),
                    child: Icon(
                      Icons.push_pin,
                      size: 17,
                      color: AppSurfaces.of(context).caution,
                    ),
                  ),
                Expanded(
                  child: Text(
                    announcement.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_canManage)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (value) {
                      if (value == 'delete') {
                        _delete(context);
                      } else {
                        AnnouncementService.instance.setPinned(
                          orgId: organization.id,
                          announcement: announcement,
                          pinned: value == 'pin',
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      if (me.postsAnnouncements)
                        PopupMenuItem(
                          value: announcement.pinned ? 'unpin' : 'pin',
                          child: Text(
                            announcement.pinned ? 'Unpin' : 'Pin to top',
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text(
                    announcement.body,
                    style: const TextStyle(fontSize: 14, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${announcement.authorName} · '
                    '${Fmt.relative(announcement.createdAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposeScreen extends StatefulWidget {
  const _ComposeScreen({required this.organization, required this.me});

  final Organization organization;
  final Employee me;

  @override
  State<_ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<_ComposeScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  bool _pinned = false;
  bool _busy = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final negative = AppSurfaces.of(context).negative;
    try {
      await AnnouncementService.instance.post(
        orgId: widget.organization.id,
        author: widget.me,
        title: _titleController.text,
        body: _bodyController.text,
        pinned: _pinned,
      );
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Announcement posted.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: negative,
        ),
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New announcement')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _titleController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _bodyController,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Message',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _pinned,
            onChanged: (value) => setState(() => _pinned = value),
            title: const Text('Pin to the top'),
            subtitle: const Text('Keeps it above newer posts'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _post,
            child: Text(_busy ? 'Posting...' : 'Post announcement'),
          ),
        ],
      ),
    );
  }
}

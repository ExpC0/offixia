import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/call.dart';
import '../models/chat.dart';
import '../models/employee.dart';
import '../models/group_call.dart';
import '../models/organization.dart';
import '../screens/group_call_screen.dart';
import 'group_call_service.dart';

class GroupCalls {
  GroupCalls._();

  static Future<void> start({
    required BuildContext context,
    required Organization organization,
    required Employee me,
    required ChatGroup chat,
    required CallKind kind,
    required Map<String, Employee> people,
  }) async {
    final video = kind == CallKind.video;
    var invited = List<String>.of(chat.memberUids);
    if (invited.length > GroupCall.maxParticipants) {
      final selected = await _pickParticipants(
        context: context,
        me: me,
        chat: chat,
        people: people,
      );
      if (selected == null) return;
      invited = [me.uid, ...selected];
    }
    final permissions = await <Permission>[
      Permission.microphone,
      if (video) Permission.camera,
    ].request();
    if (!permissions.values.every((status) => status.isGranted)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone and camera access needed.')),
        );
      }
      return;
    }

    try {
      final id = await GroupCallService.instance.start(
        orgId: organization.id,
        chat: chat,
        me: me,
        kind: kind,
        invitedUids: invited,
      );
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GroupCallScreen(
            organization: organization,
            me: me,
            callId: id,
            groupName: chat.name,
            isVideo: video,
            names: {
              for (final uid in invited)
                uid: people[uid]?.name ?? 'Participant',
            },
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  static Future<List<String>?> _pickParticipants({
    required BuildContext context,
    required Employee me,
    required ChatGroup chat,
    required Map<String, Employee> people,
  }) {
    final candidates = chat.memberUids.where((uid) => uid != me.uid).toList();
    final selected = <String>{};
    return showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Start group call'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Choose who to call'),
                    Text(
                      '${selected.length}/3 selected',
                      style: TextStyle(
                        color: selected.length == 3
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'A secure mesh call supports you plus 3 colleagues.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final uid in candidates)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: selected.contains(uid),
                          title: Text(people[uid]?.name ?? 'Group member'),
                          enabled:
                              selected.contains(uid) || selected.length < 3,
                          onChanged:
                              !selected.contains(uid) && selected.length >= 3
                              ? null
                              : (checked) {
                                  setDialogState(() {
                                    if (checked == true) {
                                      selected.add(uid);
                                    } else {
                                      selected.remove(uid);
                                    }
                                  });
                                },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(selected.toList()),
              child: Text(
                'Call ${selected.length} ${selected.length == 1 ? 'person' : 'people'}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

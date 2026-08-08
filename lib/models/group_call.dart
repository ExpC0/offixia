import 'package:cloud_firestore/cloud_firestore.dart';

import 'call.dart';

/// Signalling state for one mesh call attached to a group conversation.
class GroupCall {
  const GroupCall({
    required this.id,
    required this.chatId,
    required this.groupName,
    required this.callerUid,
    required this.callerName,
    required this.kind,
    required this.invitedUids,
    required this.joinedUids,
    required this.declinedUids,
    required this.leftUids,
    required this.status,
    this.createdAt,
    this.endedAt,
  });

  static const maxParticipants = 4;

  final String id;
  final String chatId;
  final String groupName;
  final String callerUid;
  final String callerName;
  final CallKind kind;
  final List<String> invitedUids;
  final List<String> joinedUids;
  final List<String> declinedUids;
  final List<String> leftUids;
  final String status;
  final DateTime? createdAt;
  final DateTime? endedAt;

  bool get isVideo => kind == CallKind.video;
  bool get isEnded => status == 'ended';

  bool isRingingFor(String uid) =>
      !isEnded &&
      uid != callerUid &&
      invitedUids.contains(uid) &&
      !joinedUids.contains(uid) &&
      !declinedUids.contains(uid) &&
      !leftUids.contains(uid);

  Duration get age {
    final started = createdAt;
    if (started == null) return Duration.zero;
    return DateTime.now().difference(started);
  }

  factory GroupCall.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return GroupCall(
      id: doc.id,
      chatId: data['chatId'] as String? ?? '',
      groupName: data['groupName'] as String? ?? 'Group call',
      callerUid: data['callerUid'] as String? ?? '',
      callerName: data['callerName'] as String? ?? '',
      kind: CallKind.fromName(data['kind'] as String?),
      invitedUids: (data['invitedUids'] as List?)?.cast<String>() ?? const [],
      joinedUids: (data['joinedUids'] as List?)?.cast<String>() ?? const [],
      declinedUids: (data['declinedUids'] as List?)?.cast<String>() ?? const [],
      leftUids: (data['leftUids'] as List?)?.cast<String>() ?? const [],
      status: data['status'] as String? ?? 'ended',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      endedAt: (data['endedAt'] as Timestamp?)?.toDate(),
    );
  }
}

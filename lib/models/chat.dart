import 'package:cloud_firestore/cloud_firestore.dart';

/// A conversation: either a named group or a one-to-one thread.
///
/// `memberUids` is the access control list. Security rules check membership
/// against this array on the parent document, which is why messages live
/// underneath it -- one list governs the whole thread rather than being
/// re-checked per message.
class ChatGroup {
  const ChatGroup({
    required this.id,
    required this.name,
    required this.memberUids,
    required this.createdByUid,
    this.description = '',
    this.isDirect = false,
    this.createdAt,
    this.lastMessage = '',
    this.lastMessageAt,
    this.lastSenderName = '',
    this.lastSenderUid = '',
    this.blockedBy = const [],
  });

  final String id;
  final String name;
  final List<String> memberUids;
  final String createdByUid;
  final String description;

  /// A two-person thread. Shown under the other person's name rather than a
  /// group title, and not editable as a group.
  final bool isDirect;

  final DateTime? createdAt;

  /// Denormalised preview, so the conversation list renders from one query
  /// instead of a message read per row.
  final String lastMessage;
  final DateTime? lastMessageAt;
  final String lastSenderName;

  /// Who sent the preview message. Compared against the reader's uid so an
  /// alert never fires for your own message -- names are not unique enough to
  /// decide that.
  final String lastSenderUid;

  /// Who has blocked this conversation.
  ///
  /// Held on the thread rather than on either person, because that is what the
  /// security rules can actually check: a message write already reads its
  /// parent chat, and reading a second employee document to ask "does the
  /// other side allow this?" would double the cost of every message.
  ///
  /// A block freezes the thread in both directions. Letting the blocker keep
  /// talking while the other side cannot answer would be worse than useless.
  final List<String> blockedBy;

  bool get isBlocked => blockedBy.isNotEmpty;

  bool blockedByMe(String uid) => blockedBy.contains(uid);

  /// The other person in a one-to-one thread.
  String? otherMember(String uid) {
    if (!isDirect) return null;
    for (final member in memberUids) {
      if (member != uid) return member;
    }
    return null;
  }

  bool includes(String uid) => memberUids.contains(uid);

  factory ChatGroup.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return ChatGroup(
      id: doc.id,
      name: data['name'] as String? ?? 'Conversation',
      memberUids: (data['memberUids'] as List?)?.cast<String>() ?? const [],
      createdByUid: data['createdByUid'] as String? ?? '',
      description: data['description'] as String? ?? '',
      isDirect: data['isDirect'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      lastMessage: data['lastMessage'] as String? ?? '',
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate(),
      lastSenderName: data['lastSenderName'] as String? ?? '',
      lastSenderUid: data['lastSenderUid'] as String? ?? '',
      blockedBy: (data['blockedBy'] as List?)?.cast<String>() ?? const [],
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.senderUid,
    required this.senderName,
    this.sentAt,
    this.pending = false,
  });

  final String id;
  final String text;
  final String senderUid;
  final String senderName;
  final DateTime? sentAt;

  /// True while the server timestamp is still null -- the message is in the
  /// local write queue and has not been acknowledged yet.
  final bool pending;

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final sentAt = (data['sentAt'] as Timestamp?)?.toDate();
    return ChatMessage(
      id: doc.id,
      text: data['text'] as String? ?? '',
      senderUid: data['senderUid'] as String? ?? '',
      senderName: data['senderName'] as String? ?? '',
      sentAt: sentAt,
      pending: sentAt == null,
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat.dart';
import '../models/employee.dart';
import 'db.dart';
import 'live.dart';

/// Group and direct messaging inside one company.
class ChatService {
  ChatService._();

  static final ChatService instance = ChatService._();

  /// Conversations this person belongs to, most recently active first.
  ///
  /// `arrayContains` on the member list is what makes the query and the
  /// security rule agree: a thread you are not in is neither returned nor
  /// readable.
  Stream<List<ChatGroup>> myChats(String orgId, String uid) {
    return Live.of('chats/$orgId/$uid', () {
      return Db.chats(orgId)
          .where('memberUids', arrayContains: uid)
          .orderBy('lastMessageAt', descending: true)
          .snapshots()
          .map((snap) => snap.docs.map(ChatGroup.fromDoc).toList());
    });
  }

  Stream<ChatGroup?> watch(String orgId, String chatId) {
    return Live.of('chat/$orgId/$chatId', () {
      return Db.chats(orgId)
          .doc(chatId)
          .snapshots()
          .map((doc) => doc.exists ? ChatGroup.fromDoc(doc) : null);
    });
  }

  /// Oldest last, because the message list renders reversed so new messages
  /// appear at the bottom without scrolling the whole history.
  Stream<List<ChatMessage>> messages(
    String orgId,
    String chatId, {
    int limit = 200,
  }) {
    return Live.of('messages/$orgId/$chatId/$limit', () {
      return Db.messages(orgId, chatId)
          .orderBy('sentAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snap) => snap.docs.map(ChatMessage.fromDoc).toList());
    });
  }

  Future<String> createGroup({
    required String orgId,
    required Employee creator,
    required String name,
    required String description,
    required List<Employee> members,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw Exception('Give the group a name.');
    if (members.isEmpty) {
      throw Exception('Pick at least one person to add.');
    }

    // The creator is always a member, even if they did not tick themselves.
    final uids = {creator.uid, ...members.map((m) => m.uid)}.toList();

    final doc = await Db.chats(orgId).add({
      'name': cleanName,
      'description': description.trim(),
      'memberUids': uids,
      'createdByUid': creator.uid,
      'isDirect': false,
      'createdAt': FieldValue.serverTimestamp(),
      // Seeded so the conversation sorts sensibly before anyone has spoken;
      // ordering by lastMessageAt would otherwise drop it off a descending
      // query entirely, because null sorts last and never appears.
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessage': '',
      'lastSenderName': '',
      'lastSenderUid': '',
    });

    return doc.id;
  }

  /// Opens the one-to-one thread with someone, reusing it if it exists.
  ///
  /// The id is derived from both uids sorted, so both people compute the same
  /// one and two simultaneous opens cannot create duplicate threads.
  Future<String> openDirect({
    required String orgId,
    required Employee me,
    required Employee other,
  }) async {
    final pair = [me.uid, other.uid]..sort();
    final id = 'dm_${pair.first}_${pair.last}';
    final ref = Db.chats(orgId).doc(id);

    if (!(await ref.get()).exists) {
      await ref.set({
        'name': '',
        'description': '',
        'memberUids': pair,
        'createdByUid': me.uid,
        'isDirect': true,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastSenderName': '',
        'lastSenderUid': '',
      });
    }
    return id;
  }

  Future<void> send({
    required String orgId,
    required String chatId,
    required Employee sender,
    required String text,
  }) async {
    final body = text.trim();
    if (body.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();

    batch.set(Db.messages(orgId, chatId).doc(), {
      'text': body,
      'senderUid': sender.uid,
      'senderName': sender.name,
      'sentAt': FieldValue.serverTimestamp(),
    });

    // Preview and ordering key, updated in the same batch so the list can
    // never show a thread whose last message has not landed.
    batch.update(Db.chats(orgId).doc(chatId), {
      'lastMessage': body,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSenderName': sender.name,
      'lastSenderUid': sender.uid,
    });

    await batch.commit();
  }

  /// Renames a group. Direct threads have no name of their own -- they are
  /// shown under the other person's name -- so there is nothing to rename.
  Future<void> rename({
    required String orgId,
    required String chatId,
    required String name,
    String? description,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw Exception('The group needs a name.');

    await Db.chats(orgId).doc(chatId).update({
      'name': cleanName,
      'description': ?description?.trim(),
    });
  }

  Future<void> setMembers({
    required String orgId,
    required String chatId,
    required List<String> memberUids,
  }) async {
    if (memberUids.isEmpty) {
      throw Exception('A group needs at least one member.');
    }
    await Db.chats(orgId).doc(chatId).update({'memberUids': memberUids});
  }

  /// Removing yourself from a group. The last member out deletes nothing --
  /// the history stays for anyone re-added later.
  Future<void> leave({
    required String orgId,
    required String chatId,
    required String uid,
  }) async {
    await Db.chats(orgId).doc(chatId).update({
      'memberUids': FieldValue.arrayRemove([uid]),
    });
  }

  /// Blocks or unblocks a one-to-one conversation.
  ///
  /// Only ever adds or removes yourself, which is also all the rules permit.
  Future<void> setBlocked({
    required String orgId,
    required String chatId,
    required String uid,
    required bool blocked,
  }) async {
    await Db.chats(orgId).doc(chatId).update({
      'blockedBy': blocked
          ? FieldValue.arrayUnion([uid])
          : FieldValue.arrayRemove([uid]),
    });
  }

  /// Retracts your own message. The record stays honest: nobody can edit what
  /// was said, only remove it entirely.
  Future<void> deleteMessage({
    required String orgId,
    required String chatId,
    required String messageId,
  }) async {
    await Db.messages(orgId, chatId).doc(messageId).delete();
  }

  /// Adds people to a group. Creator only, enforced by the rules.
  Future<void> addMembers({
    required String orgId,
    required String chatId,
    required List<String> uids,
  }) async {
    if (uids.isEmpty) return;
    await Db.chats(orgId).doc(chatId).update({
      'memberUids': FieldValue.arrayUnion(uids),
    });
  }

  /// Removes someone else from a group. Creator only.
  Future<void> removeMember({
    required String orgId,
    required String chatId,
    required String uid,
  }) async {
    await Db.chats(orgId).doc(chatId).update({
      'memberUids': FieldValue.arrayRemove([uid]),
    });
  }

  /// Deletes a group and its messages.
  ///
  /// Firestore does not cascade, so the messages are walked first -- left
  /// behind they would stay billable and still readable by direct path. The
  /// rules let the group's creator delete anyone's message for exactly this.
  Future<void> deleteGroup({
    required String orgId,
    required String chatId,
  }) async {
    while (true) {
      final batchDocs = await Db.messages(orgId, chatId).limit(300).get();
      if (batchDocs.docs.isEmpty) break;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in batchDocs.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (batchDocs.docs.length < 300) break;
    }

    await Db.chats(orgId).doc(chatId).delete();
  }
}

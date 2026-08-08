import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/announcement.dart';
import '../models/employee.dart';
import 'db.dart';
import 'live.dart';

/// The company feed. Everyone reads; HR and the owner write.
class AnnouncementService {
  AnnouncementService._();

  static final AnnouncementService instance = AnnouncementService._();

  /// Pinned posts first, then newest.
  ///
  /// Sorting on two fields in Firestore needs a composite index, and pinning is
  /// rare enough that ordering by date server-side and lifting the pinned ones
  /// client-side costs nothing and keeps the index list empty.
  Stream<List<Announcement>> feed(String orgId, {int limit = 50}) {
    return Live.of('announcements/$orgId/$limit', () {
      return Db.announcements(orgId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snap) {
            final items = snap.docs.map(Announcement.fromDoc).toList();
            final pinned = items.where((a) => a.pinned);
            final rest = items.where((a) => !a.pinned);
            return [...pinned, ...rest];
          });
    });
  }

  Future<void> post({
    required String orgId,
    required Employee author,
    required String title,
    required String body,
    bool pinned = false,
  }) async {
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    if (cleanTitle.isEmpty) throw Exception('Give the announcement a title.');
    if (cleanBody.isEmpty) throw Exception('Write something to announce.');

    await Db.announcements(orgId).add({
      'title': cleanTitle,
      'body': cleanBody,
      'authorUid': author.uid,
      'authorName': author.name,
      'authorPhotoUrl': author.photoUrl,
      'pinned': pinned,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setPinned({
    required String orgId,
    required Announcement announcement,
    required bool pinned,
  }) async {
    await Db.announcements(
      orgId,
    ).doc(announcement.id).update({'pinned': pinned});
  }

  Future<void> delete({
    required String orgId,
    required Announcement announcement,
  }) async {
    await Db.announcements(orgId).doc(announcement.id).delete();
  }
}

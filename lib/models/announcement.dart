import 'package:cloud_firestore/cloud_firestore.dart';

/// A company-wide post. Everyone in the org can read these; HR and the owner
/// are the only ones who can write them.
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.authorUid,
    required this.authorName,
    this.authorPhotoUrl = '',
    this.pinned = false,
    this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final String authorUid;
  final String authorName;
  final String authorPhotoUrl;
  final bool pinned;
  final DateTime? createdAt;

  factory Announcement.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Announcement(
      id: doc.id,
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      authorUid: data['authorUid'] as String? ?? '',
      authorName: data['authorName'] as String? ?? '',
      authorPhotoUrl: data['authorPhotoUrl'] as String? ?? '',
      pinned: data['pinned'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

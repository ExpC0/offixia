import 'package:cloud_firestore/cloud_firestore.dart';

/// A working group inside the company.
///
/// Deliberately orthogonal to both the designation ladder and the department
/// field: a team can hold anyone from the organization, at any rank, from any
/// department. That is the point of one -- a project pulls an engineer, someone
/// from finance and a manager together without changing who any of them
/// reports to.
///
/// Membership here grants no authority. Being in a team does not let you
/// approve anything or see anyone's records; it is a grouping, and the
/// security rules treat it as such.
class Team {
  const Team({
    required this.id,
    required this.name,
    required this.memberUids,
    required this.createdByUid,
    this.description = '',
    this.leadUid,
    this.createdAt,
  });

  final String id;
  final String name;
  final List<String> memberUids;
  final String createdByUid;
  final String description;

  /// Who runs the team. Always also a member, and shown first in the roster.
  /// Carries no extra permissions -- it is a label, not a role.
  final String? leadUid;

  final DateTime? createdAt;

  int get size => memberUids.length;

  bool includes(String uid) => memberUids.contains(uid);

  factory Team.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Team(
      id: doc.id,
      name: data['name'] as String? ?? 'Team',
      memberUids: (data['memberUids'] as List?)?.cast<String>() ?? const [],
      createdByUid: data['createdByUid'] as String? ?? '',
      description: data['description'] as String? ?? '',
      leadUid: data['leadUid'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

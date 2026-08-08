import 'package:cloud_firestore/cloud_firestore.dart';

import 'role.dart';

/// A place held for someone who has not signed in yet.
///
/// The app cannot create a Firebase Auth account on somebody else's behalf --
/// only the person signing in can do that. So "adding an employee by email"
/// records an intention: when that address signs in for the first time, the
/// membership, designation and department waiting here are applied
/// automatically, and they never see the invite-code screen.
///
/// Stored top-level and keyed by email so a user who belongs to nothing yet
/// can find their own invite. They cannot list the collection -- only read the
/// single document whose id is their own address.
class Invite {
  const Invite({
    required this.email,
    required this.orgId,
    required this.orgName,
    required this.role,
    this.department = '',
    this.jobTitle = '',
    this.invitedByUid = '',
    this.invitedByName = '',
    this.createdAt,
  });

  final String email;
  final String orgId;

  /// Denormalised so the sign-in screen can say which company is expecting
  /// them without first being allowed to read the organization document.
  final String orgName;

  final Role role;
  final String department;
  final String jobTitle;
  final String invitedByUid;
  final String invitedByName;
  final DateTime? createdAt;

  /// Email addresses are case-insensitive in practice, so the document id is
  /// always the lowercased, trimmed form. Everything reading or writing an
  /// invite must go through this.
  static String keyFor(String email) => email.trim().toLowerCase();

  factory Invite.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Invite(
      email: data['email'] as String? ?? doc.id,
      orgId: data['orgId'] as String? ?? '',
      orgName: data['orgName'] as String? ?? 'your company',
      role: Role.fromName(data['role'] as String?),
      department: data['department'] as String? ?? '',
      jobTitle: data['jobTitle'] as String? ?? '',
      invitedByUid: data['invitedByUid'] as String? ?? '',
      invitedByName: data['invitedByName'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

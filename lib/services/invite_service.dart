import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/employee.dart';
import '../models/invite.dart';
import '../models/organization.dart';
import '../models/role.dart';
import 'db.dart';

/// Bringing new people into a company.
class InviteService {
  InviteService._();

  static final InviteService instance = InviteService._();

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Pending invites for this company, so the inviter can see who has not
  /// arrived yet and withdraw one if it was a mistake.
  Stream<List<Invite>> pending(String orgId) {
    return Db.invites
        .where('orgId', isEqualTo: orgId)
        .snapshots()
        .map(
          (snap) => snap.docs.map(Invite.fromDoc).toList()
            ..sort((a, b) => a.email.compareTo(b.email)),
        );
  }

  /// Invites somebody by email address.
  ///
  /// Throws with a plain-language reason rather than letting the rules reject
  /// the write, because "you cannot invite someone into a designation at or
  /// above your own" is a sentence, not a permission error.
  Future<void> invite({
    required Organization organization,
    required Employee invitedBy,
    required String email,
    required Role role,
    String department = '',
    String jobTitle = '',
  }) async {
    final key = Invite.keyFor(email);

    if (key.isEmpty) throw Exception('Enter an email address.');
    if (!_emailPattern.hasMatch(key)) {
      throw Exception('That does not look like an email address.');
    }
    if (role.rank >= invitedBy.role.rank) {
      throw Exception(
        'You cannot invite someone as ${role.fullTitle}. Pick a designation '
        'below your own.',
      );
    }

    // Already on the staff list? Inviting again would do nothing, and saying
    // so is more use than a silent success.
    final existing = await Db.employees(organization.id)
        .where('email', isEqualTo: key)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      final person = Employee.fromDoc(existing.docs.first);
      throw Exception(
        person.active
            ? '${person.name} is already in the company.'
            : '${person.name} is already on the staff list but deactivated. '
                  'Reactivate them from their profile instead.',
      );
    }

    final held = await Db.invites.doc(key).get();
    if (held.exists && held.data()?['orgId'] != organization.id) {
      throw Exception(
        'That address has already been invited to another company.',
      );
    }

    await Db.invites.doc(key).set({
      'email': key,
      'orgId': organization.id,
      'orgName': organization.name,
      'role': role.name,
      'department': department.trim(),
      'jobTitle': jobTitle.trim(),
      'invitedByUid': invitedBy.uid,
      'invitedByName': invitedBy.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> revoke({required String email}) async {
    await Db.invites.doc(Invite.keyFor(email)).delete();
  }

  /// The invite waiting for this address, if any. Read at sign-in by someone
  /// who belongs to no company yet.
  Future<Invite?> forEmail(String email) async {
    final key = Invite.keyFor(email);
    if (key.isEmpty) return null;
    final doc = await Db.invites.doc(key).get();
    return doc.exists ? Invite.fromDoc(doc) : null;
  }
}

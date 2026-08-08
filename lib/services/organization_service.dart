import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/invite.dart';
import '../models/role.dart';
import '../models/organization.dart';
import 'db.dart';

/// Creating a company and joining one. Both are the same shape of work: write
/// an employee record, then point the user's membership at the org.
class OrganizationService {
  OrganizationService._();

  static final OrganizationService instance = OrganizationService._();

  /// Ambiguous glyphs removed -- nobody should have to guess whether the code
  /// their manager read out was a zero or an O.
  static const _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const _codeLength = 6;

  final Random _random = Random.secure();

  String _generateCode() => List.generate(
    _codeLength,
    (_) => _codeAlphabet[_random.nextInt(_codeAlphabet.length)],
  ).join();

  /// Creates the org and makes the caller its owner, in one atomic batch:
  /// org document, the owner's employee record, the membership pointer, and
  /// the public join-code lookup. A half-created company -- an org nobody
  /// belongs to, or a membership pointing at nothing -- would strand the user
  /// on a screen with no way forward, so all four land together or none do.
  Future<void> createOrganization({
    required String name,
    required int workdayStartMinutes,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('You are signed out.');

    final cleanName = name.trim();
    if (cleanName.isEmpty) throw Exception('Give your organization a name.');
    _validateWorkdayStart(workdayStartMinutes);

    final code = await _reserveUniqueCode();
    final orgRef = Db.organizations.doc();

    final batch = FirebaseFirestore.instance.batch();
    batch.set(orgRef, {
      'name': cleanName,
      'joinCode': code,
      'ownerUid': user.uid,
      'workdayStartMinutes': workdayStartMinutes,
      'employeeIdPrefix': 'OFX',
      // The founder takes 0001, so the next number handed out is 2.
      'nextEmployeeSeq': 2,
      'geofenceMetres': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(Db.employees(orgRef.id).doc(user.uid), {
      'name': user.displayName ?? 'Owner',
      'email': user.email ?? '',
      'photoUrl': user.photoURL ?? '',
      'role': Role.md.name,
      'employeeId': 'OFX0001',
      'department': '',
      'jobTitle': Role.md.fullTitle,
      'phone': '',
      'managerUid': null,
      'active': true,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    batch.set(Db.joinCodes.doc(code), {
      'orgId': orgRef.id,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(Db.memberships.doc(user.uid), {
      'orgId': orgRef.id,
      'joinedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Joins an existing org as a plain employee. The owner or HR can promote
  /// them afterwards; nobody can join straight into a privileged role.
  Future<void> joinWithCode(String rawCode) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('You are signed out.');

    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty) throw Exception('Enter the invite code.');

    final lookupRef = Db.joinCodes.doc(code);
    final initialLookup = await lookupRef.get();
    final orgId = initialLookup.data()?['orgId'] as String?;
    if (orgId == null) {
      throw Exception('That invite code does not match any organization.');
    }

    await FirebaseFirestore.instance.runTransaction((tx) async {
      // Re-read both documents inside the transaction. If the owner rotates
      // the code while somebody is joining, Firestore retries against the new
      // state instead of admitting them using a stale lookup.
      final lookup = await tx.get(lookupRef);
      final currentOrgId = lookup.data()?['orgId'] as String?;
      if (currentOrgId == null || currentOrgId != orgId) {
        throw Exception('That invite code is no longer active.');
      }

      final orgRef = Db.org(orgId);
      final org = await tx.get(orgRef);
      final data = org.data();
      if (data == null || data['joinCode'] != code) {
        throw Exception('That invite code is no longer active.');
      }

      final employeeId = _employeeIdFor(data);
      final seq = (data['nextEmployeeSeq'] as num?)?.toInt() ?? 1;
      tx.update(orgRef, {'nextEmployeeSeq': seq + 1});
      tx.set(Db.employees(orgId).doc(user.uid), {
        'employeeId': employeeId,
        'name': user.displayName ?? 'New employee',
        'email': user.email ?? '',
        'photoUrl': user.photoURL ?? '',
        'role': Role.employee.name,
        'department': '',
        'jobTitle': '',
        'phone': '',
        'managerUid': null,
        'active': true,
        'joinedAt': FieldValue.serverTimestamp(),
      });
      tx.set(Db.memberships.doc(user.uid), {
        'orgId': orgId,
        // The rules validate this proof against both the organization and the
        // non-queryable lookup document. It is private to this user.
        'joinCode': code,
        'joinedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Accepts an emailed invite: joins the company with the designation,
  /// department and job title the inviter chose, and consumes the invite.
  ///
  /// The designation is taken from the invite document rather than passed in,
  /// and the security rules check the written role against that same document
  /// -- so a tampered client cannot promote itself on the way in.
  Future<void> acceptInvite(Invite invite) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('You are signed out.');

    final signedInEmail = user.email;
    if (signedInEmail == null || signedInEmail.trim().isEmpty) {
      throw Exception('Your signed-in account has no verified email address.');
    }
    final inviteRef = Db.invites.doc(Invite.keyFor(signedInEmail));

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final inviteSnapshot = await tx.get(inviteRef);
      if (!inviteSnapshot.exists) {
        throw Exception('That invitation is no longer available.');
      }
      final currentInvite = Invite.fromDoc(inviteSnapshot);
      if (currentInvite.orgId != invite.orgId) {
        throw Exception('That invitation has changed. Please try again.');
      }

      final orgRef = Db.org(currentInvite.orgId);
      final org = await tx.get(orgRef);
      final data = org.data();
      if (data == null) {
        throw Exception('That organization no longer exists.');
      }

      final employeeId = _employeeIdFor(data);
      final seq = (data['nextEmployeeSeq'] as num?)?.toInt() ?? 1;
      tx.update(orgRef, {'nextEmployeeSeq': seq + 1});
      tx.set(Db.employees(currentInvite.orgId).doc(user.uid), {
        'employeeId': employeeId,
        'name': user.displayName ?? 'New employee',
        'email': signedInEmail,
        'photoUrl': user.photoURL ?? '',
        'role': currentInvite.role.name,
        'department': currentInvite.department,
        'jobTitle': currentInvite.jobTitle,
        'phone': '',
        'managerUid': null,
        'active': true,
        'joinedAt': FieldValue.serverTimestamp(),
      });
      tx.set(Db.memberships.doc(user.uid), {
        'orgId': currentInvite.orgId,
        'joinedAt': FieldValue.serverTimestamp(),
      });
      // Consumed atomically, so a second sign-in cannot accept it twice.
      tx.delete(inviteRef);
    });
  }

  /// Gives an existing record a staff number if it predates numbering.
  ///
  /// Called for the signed-in person only, on their own record, which is the
  /// one write the rules allow them here. That makes the backfill happen by
  /// itself as people open the app, instead of needing an admin sweep.
  Future<void> backfillOwnEmployeeId({
    required String orgId,
    required String uid,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid) throw Exception('You are signed out.');

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final orgRef = Db.org(orgId);
      final employeeRef = Db.employees(orgId).doc(uid);
      final org = await tx.get(orgRef);
      final employee = await tx.get(employeeRef);
      final data = org.data();
      if (data == null || !employee.exists) return;
      if ((employee.data()?['employeeId'] as String? ?? '').isNotEmpty) return;

      final employeeId = _employeeIdFor(data);
      final seq = (data['nextEmployeeSeq'] as num?)?.toInt() ?? 1;
      tx.update(orgRef, {'nextEmployeeSeq': seq + 1});
      tx.update(employeeRef, {'employeeId': employeeId});
    });
  }

  /// Hands out the next staff number, e.g. `OFX0084`.
  ///
  /// A transaction rather than a read-then-write: two people accepting an
  /// invite in the same second would otherwise read the same counter and be
  /// issued the same number. Numbers are not reused and need not be
  /// contiguous -- a consumed number whose join then fails simply leaves a
  /// gap, which is far better than a collision.
  String _employeeIdFor(Map<String, dynamic> org) {
    final prefix = org['employeeIdPrefix'] as String? ?? 'OFX';
    final seq = (org['nextEmployeeSeq'] as num?)?.toInt() ?? 1;
    return '$prefix${seq.toString().padLeft(4, '0')}';
  }

  /// Invalidates the current join code and publishes a fresh one atomically.
  /// Existing employees are unaffected; only future code-based joins change.
  Future<String> rotateJoinCode(String orgId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('You are signed out.');

    final org = await Db.org(orgId).get();
    final data = org.data();
    if (data == null || data['ownerUid'] != user.uid) {
      throw Exception(
        'Only the organization owner can rotate the invite code.',
      );
    }
    final oldCode = data['joinCode'] as String? ?? '';
    final newCode = await _reserveUniqueCode();

    final batch = FirebaseFirestore.instance.batch();
    batch.update(org.reference, {'joinCode': newCode});
    if (oldCode.isNotEmpty) batch.delete(Db.joinCodes.doc(oldCode));
    batch.set(Db.joinCodes.doc(newCode), {
      'orgId': orgId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return newCode;
  }

  Future<void> updateSettings({
    required String orgId,
    String? name,
    int? workdayStartMinutes,
    double? officeLat,
    double? officeLng,
    int? geofenceMetres,
  }) async {
    if (workdayStartMinutes != null) {
      _validateWorkdayStart(workdayStartMinutes);
    }
    await Db.org(orgId).update({
      'name': ?name?.trim(),
      'workdayStartMinutes': ?workdayStartMinutes,
      'officeLat': ?officeLat,
      'officeLng': ?officeLng,
      'geofenceMetres': ?geofenceMetres,
    });
  }

  void _validateWorkdayStart(int minutes) {
    if (!Organization.isValidStart(minutes)) {
      throw Exception('The office must start between 8:00 AM and 9:00 AM.');
    }
  }

  /// Deletes the company and everything under it.
  ///
  /// Irreversible, and it strands every other member by design: their
  /// membership still names an org that no longer exists, so the next time
  /// they open the app the session gate drops them back to "create or join".
  ///
  /// Firestore does not cascade. Deleting the parent document alone would
  /// leave every subcollection orphaned -- still billable, still readable by
  /// direct path -- so each collection is walked explicitly. Batches cap at
  /// 500 writes, hence the chunking.
  Future<void> deleteOrganization({
    required String orgId,
    required String confirmationName,
    required String expectedName,
  }) async {
    if (confirmationName.trim().toLowerCase() !=
        expectedName.trim().toLowerCase()) {
      throw Exception('The name you typed does not match the organization.');
    }

    final firestore = FirebaseFirestore.instance;

    final org = await Db.org(orgId).get();
    final orgData = org.data();
    final ownerUid = orgData?['ownerUid'] as String?;
    final joinCode = orgData?['joinCode'] as String?;
    if (ownerUid == null ||
        ownerUid != FirebaseAuth.instance.currentUser?.uid) {
      throw Exception('Only the organization owner can delete it.');
    }

    final employees = await Db.employees(orgId).get();
    final memberUids = {
      ownerUid,
      ...employees.docs.map((doc) => doc.id),
    }.toList();

    final collections = <Query<Map<String, dynamic>>>[
      Db.attendance(orgId),
      Db.leaveRequests(orgId),
      Db.tasks(orgId),
      Db.announcements(orgId),
      Db.teams(orgId),
      Db.invites.where('orgId', isEqualTo: orgId),
    ];

    for (final collection in collections) {
      await _deleteAll(collection);
    }

    // Call signalling contains nested candidate collections. Clear those
    // before their parent call documents; Firestore never cascades deletes.
    final calls = await Db.calls(orgId).get();
    for (final call in calls.docs) {
      await _deleteAll(call.reference.collection('callerCandidates'));
      await _deleteAll(call.reference.collection('calleeCandidates'));
    }
    await _deleteAll(Db.calls(orgId));

    // A group call has one more level: groupCall -> peer -> candidates.
    final groupCalls = await Db.groupCalls(orgId).get();
    for (final call in groupCalls.docs) {
      final peers = await call.reference.collection('peers').get();
      for (final peer in peers.docs) {
        await _deleteAll(peer.reference.collection('offerCandidates'));
        await _deleteAll(peer.reference.collection('answerCandidates'));
      }
      await _deleteAll(call.reference.collection('peers'));
    }
    await _deleteAll(Db.groupCalls(orgId));

    // Messages are nested one level deeper, so clear each thread before its
    // parent. Firestore never cascades a document deletion.
    final chats = await Db.chats(orgId).get();
    for (final chat in chats.docs) {
      await _deleteAll(Db.messages(orgId, chat.id));
    }
    await _deleteAll(Db.chats(orgId));

    await _deleteEmployeesOwnerLast(employees.docs, ownerUid);

    // The join code and every membership pointer go too, so no one is left
    // holding a reference to a company that is gone.
    await _deleteMemberships(memberUids);

    final batch = firestore.batch();
    if (joinCode != null && joinCode.isNotEmpty) {
      batch.delete(Db.joinCodes.doc(joinCode));
    }
    batch.delete(Db.org(orgId));
    await batch.commit();
  }

  Future<void> _deleteEmployeesOwnerLast(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> employees,
    String ownerUid,
  ) async {
    final others = employees.where((doc) => doc.id != ownerUid).toList();
    for (var start = 0; start < others.length; start += 400) {
      final end = min(start + 400, others.length);
      final batch = FirebaseFirestore.instance.batch();
      for (final employee in others.sublist(start, end)) {
        batch.delete(employee.reference);
      }
      await batch.commit();
    }

    // A batch that also removes other employees can lose the MD role proof
    // while those other deletes are evaluated. The owner's self-delete is a
    // separate write so authorization never depends on batch evaluation order.
    final owner = employees.where((doc) => doc.id == ownerUid).firstOrNull;
    if (owner != null) await owner.reference.delete();
  }

  Future<void> _deleteMemberships(List<String> memberUids) async {
    for (var start = 0; start < memberUids.length; start += 400) {
      final end = min(start + 400, memberUids.length);
      final batch = FirebaseFirestore.instance.batch();
      for (final uid in memberUids.sublist(start, end)) {
        batch.delete(Db.memberships.doc(uid));
      }
      await batch.commit();
    }
  }

  /// Removes one person from the company: their employee record and their
  /// membership. Their attendance and leave history stay, because those are
  /// the company's records, not the individual's.
  Future<void> leaveOrganization({
    required String orgId,
    required String uid,
  }) async {
    final batch = FirebaseFirestore.instance.batch();
    batch.delete(Db.employees(orgId).doc(uid));
    batch.delete(Db.memberships.doc(uid));
    await batch.commit();
  }

  Future<void> _deleteAll(Query<Map<String, dynamic>> collection) async {
    while (true) {
      final snapshot = await collection.limit(400).get();
      if (snapshot.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < 400) return;
    }
  }

  /// Picks a code nothing is using yet. The `create` in the batch is the real
  /// guard -- Firestore rejects a create on an existing document -- so this
  /// only has to make a collision unlikely, not impossible.
  Future<String> _reserveUniqueCode() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = _generateCode();
      final existing = await Db.joinCodes.doc(code).get();
      if (!existing.exists) return code;
    }
    throw Exception('Could not allocate an invite code. Try again.');
  }
}

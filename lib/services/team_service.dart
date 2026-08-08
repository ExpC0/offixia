import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/employee.dart';
import '../models/team.dart';
import 'db.dart';
import 'live.dart';

/// Teams inside a company: forming them, and changing who is in them.
class TeamService {
  TeamService._();

  static final TeamService instance = TeamService._();

  /// Every team in the company. Readable by everyone -- who works with whom is
  /// not confidential, and the directory is more useful when you can see it.
  Stream<List<Team>> all(String orgId) {
    return Live.of('teams/$orgId', () {
      return Db.teams(orgId)
          .orderBy('name')
          .snapshots()
          .map((snap) => snap.docs.map(Team.fromDoc).toList());
    });
  }

  Stream<Team?> watch(String orgId, String teamId) {
    return Live.of('team/$orgId/$teamId', () {
      return Db.teams(orgId)
          .doc(teamId)
          .snapshots()
          .map((doc) => doc.exists ? Team.fromDoc(doc) : null);
    });
  }

  /// The teams one person belongs to, filtered from the shared full list
  /// rather than queried separately -- the list is small, already in memory,
  /// and this avoids a second index and a second listener per profile opened.
  Stream<List<Team>> forMember(String orgId, String uid) {
    // Shared in its own right, not just `all(orgId).map(...)`: `map` returns a
    // new Stream object on every call, and StreamBuilder resubscribes whenever
    // the stream identity changes -- which is the flicker this whole layer
    // exists to avoid.
    return Live.of('teams/$orgId/member/$uid', () {
      return Db.teams(orgId)
          .orderBy('name')
          .snapshots()
          .map(
            (snap) => snap.docs
                .map(Team.fromDoc)
                .where((team) => team.includes(uid))
                .toList(),
          );
    });
  }

  Future<String> create({
    required String orgId,
    required Employee createdBy,
    required String name,
    required String description,
    required List<Employee> members,
    Employee? lead,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw Exception('Give the team a name.');
    if (members.isEmpty) throw Exception('Pick at least one member.');

    // The lead is a member whether or not they were ticked in the list.
    final uids = <String>{
      ...members.map((member) => member.uid),
      if (lead != null) lead.uid,
    }.toList();

    final doc = await Db.teams(orgId).add({
      'name': cleanName,
      'description': description.trim(),
      'memberUids': uids,
      'leadUid': lead?.uid,
      'createdByUid': createdBy.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return doc.id;
  }

  Future<void> update({
    required String orgId,
    required String teamId,
    String? name,
    String? description,
  }) async {
    final cleanName = name?.trim();
    if (cleanName != null && cleanName.isEmpty) {
      throw Exception('The team needs a name.');
    }

    await Db.teams(orgId).doc(teamId).update({
      'name': ?cleanName,
      'description': ?description?.trim(),
    });
  }

  Future<void> addMembers({
    required String orgId,
    required String teamId,
    required List<String> uids,
  }) async {
    if (uids.isEmpty) return;
    await Db.teams(orgId).doc(teamId).update({
      'memberUids': FieldValue.arrayUnion(uids),
    });
  }

  /// Removing someone. If they were the lead, the team is left without one
  /// rather than silently promoting somebody who never agreed to it.
  Future<void> removeMember({
    required String orgId,
    required String teamId,
    required String uid,
    required String? currentLeadUid,
  }) async {
    await Db.teams(orgId).doc(teamId).update({
      'memberUids': FieldValue.arrayRemove([uid]),
      if (currentLeadUid == uid) 'leadUid': null,
    });
  }

  /// Naming the lead. Passing null clears it.
  Future<void> setLead({
    required String orgId,
    required String teamId,
    required String? uid,
  }) async {
    await Db.teams(orgId).doc(teamId).update({
      'leadUid': uid,
      // A lead who is not in their own team would be a nonsense the roster
      // could not show, so joining them is part of the same write.
      if (uid != null) 'memberUids': FieldValue.arrayUnion([uid]),
    });
  }

  Future<void> delete({required String orgId, required String teamId}) async {
    await Db.teams(orgId).doc(teamId).delete();
  }
}

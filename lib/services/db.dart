import 'package:cloud_firestore/cloud_firestore.dart';

typedef Json = Map<String, dynamic>;
typedef JsonCollection = CollectionReference<Json>;
typedef JsonDoc = DocumentReference<Json>;

/// Every Firestore path in the app, in one place.
///
/// Almost everything is nested under `organizations/{orgId}`, which makes the
/// org the tenant boundary: a security rule written once at that level covers
/// the whole subtree, and no query can accidentally reach across companies.
///
/// The two exceptions are deliberate, and both exist to answer a question the
/// caller has *before* it knows an org id:
///   - `memberships/{uid}` -- "which company do I belong to?", read at sign-in.
///   - `joinCodes/{code}`  -- "which company does this invite code mean?",
///     read by someone who is not a member of anything yet. Keeping it separate
///     is what avoids granting new users permission to list every organization.
class Db {
  Db._();

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static JsonCollection get organizations =>
      _firestore.collection('organizations');

  static JsonDoc org(String orgId) => organizations.doc(orgId);

  static JsonCollection employees(String orgId) =>
      org(orgId).collection('employees');

  static JsonCollection attendance(String orgId) =>
      org(orgId).collection('attendance');

  static JsonCollection leaveRequests(String orgId) =>
      org(orgId).collection('leaveRequests');

  static JsonCollection tasks(String orgId) => org(orgId).collection('tasks');

  static JsonCollection announcements(String orgId) =>
      org(orgId).collection('announcements');

  static JsonCollection chats(String orgId) => org(orgId).collection('chats');

  /// Call signalling. Holds the WebRTC handshake only -- offer, answer and
  /// ICE candidates. No media ever passes through Firestore.
  static JsonCollection calls(String orgId) => org(orgId).collection('calls');

  /// Four-person peer-to-peer mesh call signalling.
  static JsonCollection groupCalls(String orgId) =>
      org(orgId).collection('groupCalls');

  /// Working groups. Orthogonal to the designation ladder and to departments:
  /// a team can hold anyone in the company.
  static JsonCollection teams(String orgId) => org(orgId).collection('teams');

  /// Messages hang off their conversation so one `memberUids` list on the
  /// parent governs the whole thread, rather than every message carrying its
  /// own copy of the access list.
  static JsonCollection messages(String orgId, String chatId) =>
      chats(orgId).doc(chatId).collection('messages');

  /// Invites, keyed by lowercased email and stored top-level.
  ///
  /// Top-level for the same reason as joinCodes: the person who needs to read
  /// one does not belong to any company yet, so it cannot live under the org.
  static JsonCollection get invites =>
      FirebaseFirestore.instance.collection('invites');

  static JsonCollection get memberships => _firestore.collection('memberships');

  static JsonCollection get joinCodes => _firestore.collection('joinCodes');
}

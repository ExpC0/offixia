import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/employee.dart';
import '../models/organization.dart';
import 'db.dart';
import 'invite_service.dart';
import 'live.dart';
import 'organization_service.dart';

/// Where the current user stands. Sealed, so the gate in `main.dart` has to
/// handle every case and adding a state later makes the compiler point at the
/// places that need updating.
sealed class Session {
  const Session();
}

/// Auth or the org documents are still resolving. Also the state between
/// signing in and knowing whether that user belongs anywhere.
class SessionLoading extends Session {
  const SessionLoading();
}

class SessionSignedOut extends Session {
  const SessionSignedOut();
}

/// Signed in, but not a member of any organization -- create or join one.
class SessionNeedsOrg extends Session {
  const SessionNeedsOrg(this.user);
  final User user;
}

/// Still a member on paper, but switched off by HR. Offboarding without
/// deleting the person's history.
class SessionSuspended extends Session {
  const SessionSuspended(this.organization);
  final Organization organization;
}

class SessionReady extends Session {
  const SessionReady({required this.organization, required this.me});
  final Organization organization;
  final Employee me;
}

class SessionFailed extends Session {
  const SessionFailed(this.message);
  final String message;
}

/// Resolves the signed-in user into "you are this person, at this company,
/// with this role", and keeps that live.
///
/// It is a three-level subscription -- auth -> membership -> (org, employee) --
/// and each level has to tear down the one below it when it changes, or a
/// signed-out user's listeners keep firing against documents the rules no
/// longer let them read.
class SessionService {
  SessionService._();

  static final SessionService instance = SessionService._();

  final ValueNotifier<Session> state = ValueNotifier<Session>(
    const SessionLoading(),
  );

  StreamSubscription<DocumentSnapshot<Json>>? _membershipSub;
  StreamSubscription<DocumentSnapshot<Json>>? _orgSub;
  StreamSubscription<DocumentSnapshot<Json>>? _employeeSub;
  Timer? _loadingTimeout;

  /// The uid whose listener tree is currently live, so repeated auth events
  /// for the same user do not tear everything down just to rebuild it.
  String? _trackedUid;

  /// Guards the staff-number backfill. The employee listener fires again the
  /// moment the number is written, and without this that second snapshot
  /// would start another allocation and burn a number on every round.
  bool _backfilling = false;

  String? _orgId;
  Organization? _organization;
  Employee? _me;

  /// Synchronous accessors, for the services that need an org id to build a
  /// query and would otherwise all have to take one as a parameter.
  String? get orgId => _orgId;
  Employee? get me => _me;
  Organization? get organization => _organization;

  void start() {
    // Never cancelled: this one listener is what drives the whole app, and it
    // is meant to outlive every screen. Sign-out arrives through it as a null
    // user rather than by tearing it down.
    FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);

    // Do not rely on the stream for the *initial* state: the native side
    // sends it when its listener first attaches, and on release builds --
    // which start up much faster than debug -- that event can land before
    // this Dart subscription exists and is simply lost. The symptom is an
    // app frozen on the splash spinner with a signed-in user. Seeding from
    // the synchronous currentUser makes startup deterministic; if the stream
    // then replays the same user, _onAuthChanged just resubscribes the same
    // listeners, which is harmless.
    unawaited(_onAuthChanged(FirebaseAuth.instance.currentUser));
  }

  Future<void> _onAuthChanged(User? user) async {
    // The seed in start() and the stream's own initial replay both deliver
    // the same user on a normal cold start; tearing down and rebuilding the
    // listener tree for a user already being tracked is wasted work and was
    // what exposed the cancellation race below.
    if (user != null && user.uid == _trackedUid) return;
    _trackedUid = user?.uid;

    await _stopOrgScopedListeners();

    if (user == null) {
      // Shared Firestore streams are keyed by org and uid but outlive the
      // session, so they must be torn down here. Leaving them open would keep
      // reading as the signed-out user and could serve their data to whoever
      // signs in next on this device.
      await Live.clear();
      state.value = const SessionSignedOut();
      return;
    }

    state.value = const SessionLoading();

    // A first snapshot that never arrives -- offline, blocked network, backend
    // misconfiguration -- must become a visible error, not an eternal spinner.
    // The timer only fires if nothing else has moved the state along.
    _loadingTimeout?.cancel();
    _loadingTimeout = Timer(const Duration(seconds: 20), () {
      if (state.value is SessionLoading) {
        state.value = const SessionFailed(
          'Could not reach the server. Check your connection and try again.',
        );
      }
    });

    _membershipSub = Db.memberships
        .doc(user.uid)
        .snapshots()
        .listen(
          (doc) {
            _loadingTimeout?.cancel();
            _onMembership(doc, user);
          },
          onError: (Object e) {
            _loadingTimeout?.cancel();
            state.value = SessionFailed(_readable(e, 'your membership'));
          },
        );
  }

  /// Re-runs the resolution for the current user, for a retry button on the
  /// failure screen. Clears the dedupe so the rebuild actually happens.
  void retry() {
    _trackedUid = null;
    unawaited(_onAuthChanged(FirebaseAuth.instance.currentUser));
  }

  void _onMembership(DocumentSnapshot<Json> doc, User user) {
    // Creation and joining write membership, employee and organization in one
    // local batch. The membership snapshot is optimistic and can arrive before
    // the server has committed the employee record that authorizes org reads.
    // Waiting for the acknowledged snapshot prevents a transient denied org
    // listener followed immediately by a successful one.
    if (doc.metadata.hasPendingWrites) return;

    final orgId = doc.data()?['orgId'] as String?;

    if (orgId == null || orgId.isEmpty) {
      _orgId = null;
      _organization = null;
      _me = null;
      _cancelDocumentListeners();
      // Somebody may have added this address by email before they ever signed
      // in. Accepting it here means an invited person lands straight in their
      // company rather than being asked for a code they were never given.
      unawaited(_tryInvite(user));
      state.value = SessionNeedsOrg(user);
      return;
    }

    // The membership document also updates on unrelated field changes; only
    // resubscribe when the org actually changed.
    if (orgId == _orgId) return;

    _orgId = orgId;
    _cancelDocumentListeners();

    _orgSub = Db.org(orgId).snapshots().listen(
      (snapshot) {
        _organization = snapshot.exists ? Organization.fromDoc(snapshot) : null;
        _emit(user);
      },
      onError: (Object e) =>
          state.value = SessionFailed(_readable(e, 'your organization')),
    );

    _employeeSub = Db.employees(orgId).doc(user.uid).snapshots().listen(
      (snapshot) {
        if (!snapshot.exists) {
          _recoverMissingEmployee(user);
          return;
        }
        _me = Employee.fromDoc(snapshot);
        unawaited(_ensureEmployeeId(_me!, orgId));
        _emit(user);
      },
      onError: (Object e) =>
          state.value = SessionFailed(_readable(e, 'your profile')),
    );
  }

  /// Looks for an invite matching the signed-in address and accepts it.
  ///
  /// Failure is deliberately quiet: the onboarding screen is already on
  /// display and works perfectly well with an invite code, so a missing or
  /// unusable invite should not become an error the user has to dismiss.
  Future<void> _tryInvite(User user) async {
    final email = user.email;
    if (email == null || email.isEmpty) return;

    try {
      final invite = await InviteService.instance.forEmail(email);
      if (invite == null) return;
      await OrganizationService.instance.acceptInvite(invite);
    } catch (e) {
      debugPrint('offixia: could not accept invite: $e');
    }
  }

  /// Fills in a staff number for a record that predates numbering, so the
  /// directory converges without anyone having to run a migration.
  Future<void> _ensureEmployeeId(Employee employee, String orgId) async {
    if (employee.employeeId.isNotEmpty) return;
    if (_backfilling) return;
    _backfilling = true;
    try {
      await OrganizationService.instance.backfillOwnEmployeeId(
        orgId: orgId,
        uid: employee.uid,
      );
    } catch (e) {
      debugPrint('offixia: staff number backfill failed: $e');
    } finally {
      _backfilling = false;
    }
  }

  void _recoverMissingEmployee(User user) {
    // An interrupted organization deletion can remove employees before the
    // membership pointers. Detach synchronously so a concurrent org error
    // cannot replace onboarding while the stale pointer is being removed.
    _cancelDocumentListeners();
    _orgId = null;
    _organization = null;
    _me = null;
    // Do not expose Create/Join until Firestore acknowledges removal. Creating
    // a company while the old pointer still exists turns the create into a
    // forbidden update and briefly surfaces a misleading permission error.
    state.value = const SessionLoading();
    unawaited(
      Db.memberships.doc(user.uid).delete().catchError((Object error) {
        state.value = SessionFailed(
          _readable(error, 'your previous membership'),
        );
      }),
    );
  }

  void _emit(User user) {
    final org = _organization;
    final me = _me;

    // Both listeners fire independently, so wait until each has delivered
    // something rather than flashing a half-built session.
    if (org == null || me == null) return;

    state.value = me.active
        ? SessionReady(organization: org, me: me)
        : SessionSuspended(org);
  }

  /// Called after joining or creating an org, to force the membership listener
  /// to pick the new org up even though `_orgId` guards against re-entry.
  void invalidate() {
    _orgId = null;
  }

  Future<void> _stopOrgScopedListeners() async {
    final membershipSub = _membershipSub;
    _membershipSub = null;
    _cancelDocumentListeners();
    _orgId = null;
    _organization = null;
    _me = null;
    await membershipSub?.cancel();
  }

  /// Detaches the org and employee listeners *synchronously*.
  ///
  /// The old version awaited `_orgSub?.cancel()` and nulled the fields
  /// afterwards. Called via `unawaited(...)` from `_onMembership`, it would
  /// suspend on the first cancel, resume after the caller had already
  /// assigned the *new* subscriptions into those same fields, and then
  /// cancel and null the fresh listeners it was never meant to touch. The
  /// employee stream died silently, `_emit` never saw a complete pair, and
  /// the app sat on the splash spinner forever. Capturing the old
  /// subscriptions into locals before anything can suspend makes the swap
  /// atomic from the caller's point of view.
  void _cancelDocumentListeners() {
    final orgSub = _orgSub;
    final employeeSub = _employeeSub;
    _orgSub = null;
    _employeeSub = null;
    unawaited(orgSub?.cancel());
    unawaited(employeeSub?.cancel());
  }

  String _readable(Object error, String what) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return "You don't have permission to read $what.";
    }
    return 'Could not load $what. Check your connection and try again.';
  }
}

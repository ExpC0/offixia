import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/employee.dart';
import '../models/leave_request.dart';
import 'db.dart';
import 'live.dart';

/// Filing time off, and deciding on it.
class LeaveService {
  LeaveService._();

  static final LeaveService instance = LeaveService._();

  Stream<List<LeaveRequest>> myRequests(String orgId, String uid) {
    return Live.of('leave/mine/$orgId/$uid', () {
      return Db.leaveRequests(orgId)
          .where('uid', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snap) => snap.docs.map(LeaveRequest.fromDoc).toList());
    });
  }

  /// What this approver is allowed to act on.
  ///
  /// HR and the owner see every open request; a manager sees only the people
  /// who report to them. The security rules draw the same line, so a manager
  /// who somehow issued the wider query would just get permission-denied.
  Stream<List<LeaveRequest>> pendingFor(String orgId, Employee approver) {
    final base = Db.leaveRequests(orgId).where('status', isEqualTo: 'pending');

    final query = approver.approvesAnyLeave
        ? base
        : base.where('managerUid', isEqualTo: approver.uid);

    final scope = approver.approvesAnyLeave ? 'all' : approver.uid;
    return Live.of('leave/pending/$orgId/$scope', () {
      return query
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snap) => snap.docs.map(LeaveRequest.fromDoc).toList());
    });
  }

  Future<void> submit({
    required String orgId,
    required Employee me,
    required LeaveType type,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    if (endDate.isBefore(startDate)) {
      throw Exception('The end date cannot be before the start date.');
    }

    await Db.leaveRequests(orgId).add({
      'uid': me.uid,
      'employeeName': me.name,
      'managerUid': me.managerUid,
      'type': type.name,
      'startDate': Timestamp.fromDate(_atMidnight(startDate)),
      'endDate': Timestamp.fromDate(_atMidnight(endDate)),
      'reason': reason.trim(),
      'status': LeaveStatus.pending.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> decide({
    required String orgId,
    required LeaveRequest request,
    required Employee decidedBy,
    required bool approve,
    String note = '',
  }) async {
    await Db.leaveRequests(orgId).doc(request.id).update({
      'status': (approve ? LeaveStatus.approved : LeaveStatus.rejected).name,
      'decidedByUid': decidedBy.uid,
      'decidedByName': decidedBy.name,
      'decidedAt': FieldValue.serverTimestamp(),
      'decisionNote': note.trim(),
    });
  }

  /// Withdrawing your own request. Only meaningful while it is still pending --
  /// an approved absence has to be undone by whoever approved it.
  Future<void> cancel({
    required String orgId,
    required LeaveRequest request,
  }) async {
    if (!request.isPending) {
      throw Exception('Only a pending request can be cancelled.');
    }
    await Db.leaveRequests(
      orgId,
    ).doc(request.id).update({'status': LeaveStatus.cancelled.name});
  }

  /// Dates are the unit here, not instants -- stripping the time keeps a
  /// request filed at 11pm from counting as a different day than the picker
  /// showed.
  DateTime _atMidnight(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

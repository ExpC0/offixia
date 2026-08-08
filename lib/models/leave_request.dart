import 'package:cloud_firestore/cloud_firestore.dart';

enum LeaveType {
  annual('Annual leave'),
  sick('Sick leave'),
  casual('Casual leave'),
  unpaid('Unpaid leave');

  const LeaveType(this.label);
  final String label;

  static LeaveType fromName(String? name) => LeaveType.values.firstWhere(
    (type) => type.name == name,
    orElse: () => LeaveType.annual,
  );
}

enum LeaveStatus {
  pending('Pending'),
  approved('Approved'),
  rejected('Rejected'),
  cancelled('Cancelled');

  const LeaveStatus(this.label);
  final String label;

  static LeaveStatus fromName(String? name) => LeaveStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => LeaveStatus.pending,
  );
}

/// A time-off request and the decision made on it.
///
/// `employeeName` is denormalised onto the request so an approvals list renders
/// from one query instead of one read per row. Firestore has no joins, and this
/// is the standard trade: a stale name is harmless, an N+1 read is not.
class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.uid,
    required this.employeeName,
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.managerUid,
    this.reason = '',
    this.createdAt,
    this.decidedByUid,
    this.decidedByName,
    this.decidedAt,
    this.decisionNote = '',
  });

  final String id;
  final String uid;
  final String employeeName;

  /// Copied off the employee record when the request is filed, so a manager's
  /// approvals list is a single indexed query rather than a scan of everyone's
  /// requests filtered client-side. It also gives the security rules something
  /// local to check when deciding who may approve this row.
  final String? managerUid;
  final LeaveType type;
  final DateTime startDate;
  final DateTime endDate;
  final LeaveStatus status;
  final String reason;
  final DateTime? createdAt;
  final String? decidedByUid;
  final String? decidedByName;
  final DateTime? decidedAt;
  final String decisionNote;

  /// Inclusive of both ends -- one day off is one day, not zero.
  int get days => endDate.difference(startDate).inDays + 1;

  bool get isPending => status == LeaveStatus.pending;

  factory LeaveRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final start = (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now();
    return LeaveRequest(
      id: doc.id,
      uid: data['uid'] as String? ?? '',
      employeeName: data['employeeName'] as String? ?? '',
      type: LeaveType.fromName(data['type'] as String?),
      startDate: start,
      endDate: (data['endDate'] as Timestamp?)?.toDate() ?? start,
      status: LeaveStatus.fromName(data['status'] as String?),
      managerUid: data['managerUid'] as String?,
      reason: data['reason'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      decidedByUid: data['decidedByUid'] as String?,
      decidedByName: data['decidedByName'] as String?,
      decidedAt: (data['decidedAt'] as Timestamp?)?.toDate(),
      decisionNote: data['decisionNote'] as String? ?? '',
    );
  }
}

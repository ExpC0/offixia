import 'package:cloud_firestore/cloud_firestore.dart';

import 'permission.dart';
import 'role.dart';

/// A person's record inside one organization.
///
/// The document id is the Firebase Auth uid, which is what lets the security
/// rules answer "what is the caller allowed to do here?" with a single
/// `get()` rather than a query.
class Employee {
  const Employee({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.photoUrl = '',
    this.department = '',
    this.jobTitle = '',
    this.phone = '',
    this.managerUid,
    this.joinedAt,
    this.active = true,
    this.grants = const {},
    this.employeeId = '',
  });

  final String uid;
  final String name;
  final String email;
  final Role role;
  final String photoUrl;
  final String department;
  final String jobTitle;
  final String phone;
  final String? managerUid;
  final DateTime? joinedAt;
  final bool active;

  /// Human-readable staff number, e.g. `OFX0084`. Unique within the company
  /// and never reused, so it stays a stable way to refer to someone in
  /// conversation and on paperwork -- unlike the auth uid, which nobody can
  /// read out loud.
  ///
  /// Empty for records created before numbering existed; the directory
  /// backfills those.
  final String employeeId;

  /// Authorities granted to this person individually, on top of their
  /// designation. Only a GM or the MD can change these.
  final Set<Permission> grants;

  /// The single question the UI should ask about authority. Designation first,
  /// then any individual grant -- grants only ever widen.
  bool can(Permission permission) =>
      role.confers(permission) || grants.contains(permission);

  /// True when this person holds an authority their designation would not
  /// normally give them, so the people editor can say where it came from.
  bool isGranted(Permission permission) =>
      grants.contains(permission) && !role.confers(permission);

  // Named shortcuts for the checks screens make constantly. They exist so no
  // screen reaches for `role.canX` directly -- doing that ignores individual
  // grants, which is what made a granted approver see an empty queue and get
  // permission-denied when they acted anyway.

  /// Decides leave for anyone in the company, by designation or by grant.
  bool get approvesAnyLeave => can(Permission.approveLeave);

  /// Has some approval role at all: company-wide, or a manager over their own
  /// reports. Gates whether the approvals queue is worth showing.
  bool get approvesSomeLeave => role.canApproveLeave || approvesAnyLeave;

  bool get assignsTasks => can(Permission.assignTasks);
  bool get postsAnnouncements => can(Permission.postAnnouncements);
  bool get viewsAllAttendance => can(Permission.viewAllAttendance);
  bool get managesPeople => can(Permission.managePeople);
  bool get invitesEmployees => can(Permission.inviteEmployees);
  bool get managesTeams => can(Permission.manageTeams);

  /// Whether this person may decide a leave request. Mirrors the security
  /// rule, so the UI stops offering an action the server will refuse.
  ///
  /// Nobody signs off their own absence -- not even HR, whose own leave
  /// escalates to whoever is above them. The single exception is the founder,
  /// identified by [ownerUid] rather than by title, because there is nobody
  /// above them and a one-person company must still be able to function.
  bool canDecide({
    required String requesterUid,
    required String? managerUid,
    required String ownerUid,
  }) {
    if (requesterUid == uid) return uid == ownerUid;
    return approvesAnyLeave || (role.canApproveLeave && managerUid == uid);
  }

  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  /// What to show under someone's name in a list: job title, department, or
  /// failing both, the role they hold.
  String get subtitle {
    if (jobTitle.isNotEmpty && department.isNotEmpty) {
      return '$jobTitle · $department';
    }
    if (jobTitle.isNotEmpty) return jobTitle;
    if (department.isNotEmpty) return department;
    return role.label;
  }

  factory Employee.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Employee(
      uid: doc.id,
      name: (data['name'] as String?)?.trim().isNotEmpty == true
          ? data['name'] as String
          : 'Unnamed',
      email: data['email'] as String? ?? '',
      role: Role.fromName(data['role'] as String?),
      photoUrl: data['photoUrl'] as String? ?? '',
      department: data['department'] as String? ?? '',
      jobTitle: data['jobTitle'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      managerUid: data['managerUid'] as String?,
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate(),
      active: data['active'] as bool? ?? true,
      grants: Permission.parse(data['grants']),
      employeeId: data['employeeId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'email': email,
    'role': role.name,
    'photoUrl': photoUrl,
    'department': department,
    'jobTitle': jobTitle,
    'phone': phone,
    'managerUid': managerUid,
    'active': active,
    'grants': grants.map((permission) => permission.id).toList(),
    'employeeId': employeeId,
  };
}

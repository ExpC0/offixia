/// Individual authorities that can be granted to one named person, on top of
/// whatever their designation already allows.
///
/// Designation covers the common case; this covers the real office, where an
/// admin officer signs off leave without being HR, or one senior engineer
/// assigns work without being made a manager. A grant only ever *adds* --
/// it can never take away what a role confers, so there is one direction to
/// reason about when asking "why can this person do that?".
enum Permission {
  approveLeave(
    'approveLeave',
    'Approve leave',
    'Decide any leave request in the company',
  ),
  assignTasks('assignTasks', 'Assign tasks', 'Create and hand out work'),
  postAnnouncements(
    'postAnnouncements',
    'Post announcements',
    'Write to the company feed',
  ),
  viewAllAttendance(
    'viewAllAttendance',
    'View all attendance',
    "See everyone's check-in records",
  ),
  managePeople(
    'managePeople',
    'Manage people',
    'Change designations, reporting lines and access',
  ),
  inviteEmployees(
    'inviteEmployees',
    'Add people',
    'Invite new employees to the company by email',
  ),
  manageTeams(
    'manageTeams',
    'Manage teams',
    'Create teams and choose who belongs to them',
  );

  const Permission(this.id, this.label, this.description);

  /// Stored on the employee document, so it must stay stable even if the enum
  /// is reordered or renamed in Dart.
  final String id;
  final String label;
  final String description;

  static Permission? fromId(String? id) {
    for (final permission in Permission.values) {
      if (permission.id == id) return permission;
    }
    return null;
  }

  static Set<Permission> parse(Object? raw) {
    if (raw is! List) return const {};
    return raw
        .map((entry) => Permission.fromId(entry as String?))
        .nonNulls
        .toSet();
  }
}

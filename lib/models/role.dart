import 'permission.dart';

/// Designations inside the company, and what each is allowed to do.
///
/// `rank` is the whole authorisation model in one number: every capability is
/// "your rank is at least X". Firestore's rules encode the same ladder, and
/// the two must agree -- the rules are what actually enforces this, the
/// getters here only decide what the UI bothers to show.
enum Role {
  employee('Employee', 'Employee', 0),
  manager('Manager', 'Team Manager', 1),
  hr('HR', 'Human Resources', 2),
  dgm('DGM', 'Deputy General Manager', 3),
  gm('GM', 'General Manager', 4),
  md('MD', 'Managing Director', 5);

  const Role(this.label, this.fullTitle, this.rank);

  /// Short form, for chips and dense lists.
  final String label;

  /// Spelled out, for profiles and the people editor where there is room.
  final String fullTitle;

  final int rank;

  /// `boss` was the original name for the top role. Existing employee
  /// documents still carry it, so it has to keep resolving or those accounts
  /// silently demote to Employee on the next read.
  static Role fromName(String? name) {
    if (name == 'boss') return Role.md;
    return Role.values.firstWhere(
      (role) => role.name == name,
      orElse: () => Role.employee,
    );
  }

  bool get atLeastManager => rank >= Role.manager.rank;
  bool get atLeastHr => rank >= Role.hr.rank;
  bool get atLeastDgm => rank >= Role.dgm.rank;
  bool get atLeastGm => rank >= Role.gm.rank;

  /// Managers decide for their own reports; HR and above for anyone.
  bool get canApproveLeave => atLeastManager;
  bool get canApproveAnyLeave => atLeastHr;

  bool get canAssignTasks => atLeastManager;
  bool get canViewTeamAttendance => atLeastManager;
  bool get canPostAnnouncements => atLeastHr;
  bool get canManagePeople => atLeastHr;

  /// Bringing new people into the company. HR's job by designation, and the
  /// most commonly delegated authority -- an office administrator often does
  /// the onboarding without holding HR's other powers.
  bool get canInviteEmployees => atLeastHr;

  /// Company-wide rollups rather than just one team.
  bool get canViewCompanyReports => atLeastDgm;

  /// Forming teams and deciding who is in them. Sits with the GM: a team cuts
  /// across departments and reporting lines, so drawing one is an act of
  /// organizational design rather than day-to-day people admin.
  bool get canManageTeams => atLeastGm;

  /// Handing an individual authority to one named person, outside the normal
  /// designation ladder. Deliberately the narrowest power in the app: it is
  /// how the ladder gets bypassed, so it sits with the GM and the MD only.
  bool get canGrantAuthority => atLeastGm;

  /// Workday hours, geofence -- the settings that change how everyone is
  /// measured -- plus deleting the company outright.
  bool get canEditOrgSettings => this == Role.md;
  bool get canDeleteOrganization => this == Role.md;

  /// You can never hand out a designation at or above your own, so HR cannot
  /// mint a second MD and a DGM cannot promote a peer past themselves.
  bool canAssignRole(Role target) => canManagePeople && target.rank < rank;

  List<Role> get assignableRoles =>
      Role.values.where(canAssignRole).toList(growable: false);

  /// Whether the designation alone confers this authority. An individual grant
  /// on an employee record can add to this, never subtract from it.
  bool confers(Permission permission) => switch (permission) {
    Permission.approveLeave => canApproveAnyLeave,
    Permission.assignTasks => canAssignTasks,
    Permission.postAnnouncements => canPostAnnouncements,
    Permission.viewAllAttendance => canViewTeamAttendance,
    Permission.managePeople => canManagePeople,
    Permission.inviteEmployees => canInviteEmployees,
    Permission.manageTeams => canManageTeams,
  };
}

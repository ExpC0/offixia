import 'package:flutter_test/flutter_test.dart';
import 'package:offixia/models/permission.dart';
import 'package:offixia/models/role.dart';

void main() {
  teamAuthorityTests();
  group('Role ladder', () {
    test('ranks ascend from employee to MD', () {
      expect(Role.employee.rank, lessThan(Role.manager.rank));
      expect(Role.manager.rank, lessThan(Role.hr.rank));
      expect(Role.hr.rank, lessThan(Role.dgm.rank));
      expect(Role.dgm.rank, lessThan(Role.md.rank));
    });

    test('unknown or missing role names fall back to employee', () {
      expect(Role.fromName(null), Role.employee);
      expect(Role.fromName('superuser'), Role.employee);
      expect(Role.fromName('hr'), Role.hr);
      expect(Role.fromName('dgm'), Role.dgm);
    });

    test('the retired "boss" name still resolves to MD', () {
      // Employee documents written before the rename still carry it; letting
      // it fall through to employee would silently demote the owner.
      expect(Role.fromName('boss'), Role.md);
    });
  });

  group('capabilities', () {
    test('an employee can do none of the privileged things', () {
      const role = Role.employee;
      expect(role.canApproveLeave, isFalse);
      expect(role.canAssignTasks, isFalse);
      expect(role.canPostAnnouncements, isFalse);
      expect(role.canManagePeople, isFalse);
      expect(role.canEditOrgSettings, isFalse);
    });

    test('a manager approves and assigns but does not run HR', () {
      const role = Role.manager;
      expect(role.canApproveLeave, isTrue);
      expect(role.canAssignTasks, isTrue);
      expect(role.canViewTeamAttendance, isTrue);
      // Only for their own reports, which the query and rules enforce.
      expect(role.canApproveAnyLeave, isFalse);
      expect(role.canPostAnnouncements, isFalse);
      expect(role.canManagePeople, isFalse);
    });

    test('HR manages people and posts, but does not own the org', () {
      const role = Role.hr;
      expect(role.canApproveAnyLeave, isTrue);
      expect(role.canPostAnnouncements, isTrue);
      expect(role.canManagePeople, isTrue);
      expect(role.canEditOrgSettings, isFalse);
    });

    test('only the MD edits org settings or deletes the company', () {
      expect(Role.md.canEditOrgSettings, isTrue);
      expect(Role.md.canDeleteOrganization, isTrue);
      expect(Role.gm.canEditOrgSettings, isFalse);
      expect(Role.gm.canDeleteOrganization, isFalse);
    });

    test('granting individual authority stops at GM', () {
      expect(Role.md.canGrantAuthority, isTrue);
      expect(Role.gm.canGrantAuthority, isTrue);
      // HR administers people but cannot hand out authority off-ladder.
      expect(Role.dgm.canGrantAuthority, isFalse);
      expect(Role.hr.canGrantAuthority, isFalse);
    });
  });

  group('canAssignRole', () {
    test('nobody can hand out a role at or above their own', () {
      expect(Role.hr.canAssignRole(Role.hr), isFalse);
      expect(Role.hr.canAssignRole(Role.md), isFalse);
      expect(Role.md.canAssignRole(Role.md), isFalse);
    });

    test('HR can promote up to manager', () {
      expect(Role.hr.canAssignRole(Role.employee), isTrue);
      expect(Role.hr.canAssignRole(Role.manager), isTrue);
    });

    test('roles without people-management cannot assign at all', () {
      expect(Role.manager.canAssignRole(Role.employee), isFalse);
      expect(Role.employee.canAssignRole(Role.employee), isFalse);
    });

    test('assignableRoles matches canAssignRole', () {
      expect(Role.md.assignableRoles, [
        Role.employee,
        Role.manager,
        Role.hr,
        Role.dgm,
        Role.gm,
      ]);
      expect(Role.hr.assignableRoles, [Role.employee, Role.manager]);
      expect(Role.manager.assignableRoles, isEmpty);
      expect(Role.employee.assignableRoles, isEmpty);
    });
  });
}

void teamAuthorityTests() {
  group('team authority', () {
    test('forming a team stops at GM', () {
      expect(Role.md.canManageTeams, isTrue);
      expect(Role.gm.canManageTeams, isTrue);
      // A team cuts across reporting lines, so it is not HR's day-to-day
      // people admin and not a DGM's either.
      expect(Role.dgm.canManageTeams, isFalse);
      expect(Role.hr.canManageTeams, isFalse);
      expect(Role.manager.canManageTeams, isFalse);
      expect(Role.employee.canManageTeams, isFalse);
    });

    test('manageTeams is grantable like any other authority', () {
      expect(Role.gm.confers(Permission.manageTeams), isTrue);
      expect(Role.employee.confers(Permission.manageTeams), isFalse);
    });

    test('inviting people is HR and above by designation', () {
      expect(Role.hr.canInviteEmployees, isTrue);
      expect(Role.manager.canInviteEmployees, isFalse);
      expect(Role.employee.confers(Permission.inviteEmployees), isFalse);
    });
  });
}

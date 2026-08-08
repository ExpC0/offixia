import 'package:flutter_test/flutter_test.dart';
import 'package:offixia/models/attendance.dart';
import 'package:offixia/models/call.dart';
import 'package:offixia/models/employee.dart';
import 'package:offixia/models/group_call.dart';
import 'package:offixia/models/permission.dart';
import 'package:offixia/models/leave_request.dart';
import 'package:offixia/models/organization.dart';
import 'package:offixia/models/role.dart';
import 'package:offixia/models/work_task.dart';

Employee employee({String name = 'Ada Lovelace'}) =>
    Employee(uid: 'u1', name: name, email: 'a@b.c', role: Role.employee);

AttendanceRecord record({DateTime? checkIn, DateTime? checkOut}) =>
    AttendanceRecord(
      id: 'u1_2026-08-07',
      uid: 'u1',
      employeeName: 'Ada',
      date: '2026-08-07',
      checkInAt: checkIn,
      checkOutAt: checkOut,
    );

void main() {
  authorityTests();
  group('Organization workday', () {
    test('allows starts from 8 through 9 AM', () {
      expect(Organization.isValidStart(8 * 60), isTrue);
      expect(Organization.isValidStart(8 * 60 + 30), isTrue);
      expect(Organization.isValidStart(9 * 60), isTrue);
      expect(Organization.isValidStart(7 * 60 + 59), isFalse);
      expect(Organization.isValidStart(9 * 60 + 1), isFalse);
    });

    test('ends nine hours after the configured start', () {
      const organization = Organization(
        id: 'org',
        name: 'Office',
        joinCode: 'ABC123',
        ownerUid: 'owner',
        workdayStartMinutes: 8 * 60 + 30,
      );

      expect(organization.workdayEndMinutes, 17 * 60 + 30);
      expect(Organization.workDuration, const Duration(hours: 8));
      expect(Organization.breakDuration, const Duration(hours: 1));
    });
  });

  group('Employee.initials', () {
    test('takes first and last initial', () {
      expect(employee().initials, 'AL');
    });

    test('handles a single name', () {
      expect(employee(name: 'Prince').initials, 'P');
    });

    test('ignores extra whitespace between names', () {
      expect(employee(name: '  Ada   Byron   Lovelace  ').initials, 'AL');
    });

    test('falls back rather than crashing on an empty name', () {
      expect(employee(name: '   ').initials, '?');
    });
  });

  group('Employee.subtitle', () {
    test('prefers job title and department together', () {
      const person = Employee(
        uid: 'u',
        name: 'Ada',
        email: '',
        role: Role.employee,
        jobTitle: 'Engineer',
        department: 'Platform',
      );
      expect(person.subtitle, 'Engineer · Platform');
    });

    test('falls back to the role when nothing else is set', () {
      expect(employee().subtitle, 'Employee');
    });
  });

  group('AttendanceRecord', () {
    test('dateKey zero-pads so keys sort lexicographically', () {
      expect(AttendanceRecord.dateKey(DateTime(2026, 1, 9)), '2026-01-09');
      // The padding is the whole point: without it "2026-1-9" would sort
      // after "2026-10-01".
      expect(
        AttendanceRecord.dateKey(
          DateTime(2026, 10, 1),
        ).compareTo(AttendanceRecord.dateKey(DateTime(2026, 1, 9))),
        greaterThan(0),
      );
    });

    test('idFor combines uid and date', () {
      expect(AttendanceRecord.idFor('abc', '2026-08-07'), 'abc_2026-08-07');
    });

    test('worked is the span between check in and check out', () {
      final value = record(
        checkIn: DateTime(2026, 8, 7, 9),
        checkOut: DateTime(2026, 8, 7, 17, 30),
      );
      expect(value.worked, const Duration(hours: 8, minutes: 30));
      expect(value.isComplete, isTrue);
      expect(value.isOpen, isFalse);
    });

    test('an open day is still counting', () {
      final value = record(
        checkIn: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(value.isOpen, isTrue);
      expect(value.worked.inMinutes, greaterThanOrEqualTo(119));
    });

    test('worked is zero before checking in', () {
      expect(record().worked, Duration.zero);
    });
  });

  group('LeaveRequest.days', () {
    LeaveRequest range(DateTime start, DateTime end) => LeaveRequest(
      id: 'l1',
      uid: 'u1',
      employeeName: 'Ada',
      type: LeaveType.annual,
      startDate: start,
      endDate: end,
      status: LeaveStatus.pending,
    );

    test('a single day counts as one, not zero', () {
      expect(range(DateTime(2026, 8, 7), DateTime(2026, 8, 7)).days, 1);
    });

    test('both ends are inclusive', () {
      expect(range(DateTime(2026, 8, 7), DateTime(2026, 8, 11)).days, 5);
    });
  });

  group('WorkTask.isOverdue', () {
    WorkTask task({DateTime? dueAt, TaskStatus status = TaskStatus.todo}) =>
        WorkTask(
          id: 't1',
          title: 'Ship it',
          assigneeUid: 'u1',
          assigneeName: 'Ada',
          createdByUid: 'u2',
          createdByName: 'Boss',
          priority: TaskPriority.normal,
          status: status,
          dueAt: dueAt,
        );

    test('past due and unfinished is overdue', () {
      expect(
        task(dueAt: DateTime.now().subtract(const Duration(days: 1))).isOverdue,
        isTrue,
      );
    });

    test('a finished task is never overdue, even if it was late', () {
      expect(
        task(
          dueAt: DateTime.now().subtract(const Duration(days: 1)),
          status: TaskStatus.done,
        ).isOverdue,
        isFalse,
      );
    });

    test('no due date means never overdue', () {
      expect(task().isOverdue, isFalse);
    });
  });

  group('GroupCall invitation state', () {
    GroupCall call({
      List<String> joined = const ['caller'],
      List<String> declined = const [],
      List<String> left = const [],
      String status = 'ringing',
    }) => GroupCall(
      id: 'call',
      chatId: 'chat',
      groupName: 'Design',
      callerUid: 'caller',
      callerName: 'Ada',
      kind: CallKind.audio,
      invitedUids: const ['caller', 'one', 'two', 'three'],
      joinedUids: joined,
      declinedUids: declined,
      leftUids: left,
      status: status,
    );

    test('mesh capacity is four phones including the caller', () {
      expect(GroupCall.maxParticipants, 4);
      expect(call().invitedUids, hasLength(4));
    });

    test('only an unanswered invite keeps ringing', () {
      expect(call().isRingingFor('one'), isTrue);
      expect(call().isRingingFor('caller'), isFalse);
      expect(call().isRingingFor('stranger'), isFalse);
      expect(
        call(joined: const ['caller', 'one']).isRingingFor('one'),
        isFalse,
      );
      expect(call(declined: const ['one']).isRingingFor('one'), isFalse);
      expect(call(left: const ['one']).isRingingFor('one'), isFalse);
    });

    test('an ended call never rings again', () {
      expect(call(status: 'ended').isRingingFor('one'), isFalse);
    });
  });
}

Employee withRole(
  Role role, {
  Set<Permission> grants = const {},
  String uid = 'u1',
}) => Employee(
  uid: uid,
  name: 'Test Person',
  email: 't@x.c',
  role: role,
  grants: grants,
);

void authorityTests() {
  group('Employee.can — grants widen, never narrow', () {
    test('an employee with an approveLeave grant approves company-wide', () {
      final person = withRole(Role.employee, grants: {Permission.approveLeave});
      expect(person.approvesAnyLeave, isTrue);
      expect(person.isGranted(Permission.approveLeave), isTrue);
    });

    test('HR approves company-wide from designation alone, ungranted', () {
      final person = withRole(Role.hr);
      expect(person.approvesAnyLeave, isTrue);
      // Not "granted" -- it comes from the designation, so the people editor
      // must show it as locked rather than as an individual grant.
      expect(person.isGranted(Permission.approveLeave), isFalse);
    });

    test('a grant cannot remove what the designation already gives', () {
      final person = withRole(Role.hr, grants: const {});
      expect(person.can(Permission.postAnnouncements), isTrue);
    });
  });

  group('Employee.canDecide', () {
    test('nobody signs off their own leave, not even HR', () {
      final hr = withRole(Role.hr, uid: 'hr1');
      expect(
        hr.canDecide(
          requesterUid: 'hr1',
          managerUid: null,
          ownerUid: 'founder',
        ),
        isFalse,
      );
    });

    test('the founder is the one self-approval exception', () {
      final founder = withRole(Role.md, uid: 'founder');
      expect(
        founder.canDecide(
          requesterUid: 'founder',
          managerUid: null,
          ownerUid: 'founder',
        ),
        isTrue,
      );
    });

    test('holding the MD title is not enough — it is identity, not rank', () {
      // Someone promoted to MD who did not create the company still answers
      // to the founder for their own absence.
      final promoted = withRole(Role.md, uid: 'promoted');
      expect(
        promoted.canDecide(
          requesterUid: 'promoted',
          managerUid: null,
          ownerUid: 'founder',
        ),
        isFalse,
      );
    });

    test('a manager decides only for their own reports', () {
      final manager = withRole(Role.manager, uid: 'm1');
      expect(
        manager.canDecide(
          requesterUid: 'e1',
          managerUid: 'm1',
          ownerUid: 'founder',
        ),
        isTrue,
      );
      expect(
        manager.canDecide(
          requesterUid: 'e2',
          managerUid: 'other',
          ownerUid: 'founder',
        ),
        isFalse,
      );
    });

    test('a granted approver decides for anyone but themselves', () {
      final granted = withRole(
        Role.employee,
        uid: 'g1',
        grants: {Permission.approveLeave},
      );
      expect(
        granted.canDecide(
          requesterUid: 'someone',
          managerUid: null,
          ownerUid: 'founder',
        ),
        isTrue,
      );
      expect(
        granted.canDecide(
          requesterUid: 'g1',
          managerUid: null,
          ownerUid: 'founder',
        ),
        isFalse,
      );
    });
  });
}

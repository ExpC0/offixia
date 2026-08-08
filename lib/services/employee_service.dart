import '../models/employee.dart';
import '../models/permission.dart';
import '../models/role.dart';
import 'db.dart';
import 'live.dart';

/// The people directory, and the HR edits made against it.
class EmployeeService {
  EmployeeService._();

  static final EmployeeService instance = EmployeeService._();

  Stream<List<Employee>> directory(String orgId) {
    return Live.of('directory/$orgId', () {
      return Db.employees(orgId)
          .orderBy('name')
          .snapshots()
          .map((snap) => snap.docs.map(Employee.fromDoc).toList());
    });
  }

  Stream<Employee?> watch(String orgId, String uid) {
    return Live.of('employee/$orgId/$uid', () {
      return Db.employees(orgId)
          .doc(uid)
          .snapshots()
          .map((doc) => doc.exists ? Employee.fromDoc(doc) : null);
    });
  }

  /// Fields a person may change about themselves. Deliberately excludes `role`
  /// and `active` -- those are HR's to set, and the security rules reject them
  /// coming from the employee's own client.
  Future<void> updateOwnProfile({
    required String orgId,
    required String uid,
    required String name,
    required String jobTitle,
    required String department,
    required String phone,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw Exception('Your name cannot be empty.');

    await Db.employees(orgId).doc(uid).update({
      'name': cleanName,
      'jobTitle': jobTitle.trim(),
      'department': department.trim(),
      'phone': phone.trim(),
    });
  }

  Future<void> updateAsAdmin({
    required String orgId,
    required Employee target,
    Role? role,
    String? managerUid,
    bool clearManager = false,
    bool? active,
    String? department,
    String? jobTitle,
  }) async {
    await Db.employees(orgId).doc(target.uid).update({
      'role': ?role?.name,
      // A null managerUid is a legitimate value (nobody reports to anyone at
      // the top), so "leave it alone" and "clear it" need separate signals.
      if (clearManager) 'managerUid': null else 'managerUid': ?managerUid,
      'active': ?active,
      'department': ?department?.trim(),
      'jobTitle': ?jobTitle?.trim(),
    });
  }

  /// Replaces the set of individual authorities held by one person.
  ///
  /// Separate from [updateAsAdmin] because the rules gate it on a higher rank:
  /// changing someone's department is HR's job, handing them an authority
  /// outside their designation is the GM's.
  Future<void> setGrants({
    required String orgId,
    required Employee target,
    required Set<Permission> grants,
  }) async {
    await Db.employees(orgId).doc(target.uid).update({
      'grants': grants.map((permission) => permission.id).toList(),
    });
  }
}

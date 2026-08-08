import 'package:cloud_firestore/cloud_firestore.dart';

/// A company. Every other collection in the app lives underneath one of these,
/// so the org id is effectively the tenant boundary.
class Organization {
  static const earliestStartMinutes = 8 * 60;
  static const latestStartMinutes = 9 * 60;
  static const officeDuration = Duration(hours: 9);
  static const workDuration = Duration(hours: 8);
  static const breakDuration = Duration(hours: 1);

  const Organization({
    required this.id,
    required this.name,
    required this.joinCode,
    this.employeeIdPrefix = 'OFX',
    this.nextEmployeeSeq = 1,
    required this.ownerUid,
    this.createdAt,
    this.workdayStartMinutes = 9 * 60,
    this.officeLat,
    this.officeLng,
    this.geofenceMetres = 0,
  });

  final String id;
  final String name;

  /// Short code a new hire types to join. Stored again as its own top-level
  /// `joinCodes/{code}` document so joining does not require permission to
  /// list every organization in the database.
  final String joinCode;

  /// Prefix for staff numbers, e.g. `OFX` giving `OFX0001`.
  final String employeeIdPrefix;

  /// The next staff number to hand out. Incremented in a transaction so two
  /// people joining at the same moment cannot be given the same number.
  final int nextEmployeeSeq;
  final String ownerUid;
  final DateTime? createdAt;

  /// Minutes past midnight. Check-ins after this are flagged late.
  final int workdayStartMinutes;

  int get workdayEndMinutes => workdayStartMinutes + officeDuration.inMinutes;

  static bool isValidStart(int minutes) =>
      minutes >= earliestStartMinutes && minutes <= latestStartMinutes;

  final double? officeLat;
  final double? officeLng;

  /// 0 disables the geofence, which is the default -- an office that has not
  /// set its coordinates should not lock everyone out of checking in.
  final int geofenceMetres;

  bool get hasGeofence =>
      geofenceMetres > 0 && officeLat != null && officeLng != null;

  factory Organization.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Organization(
      id: doc.id,
      name: data['name'] as String? ?? 'Organization',
      joinCode: data['joinCode'] as String? ?? '',
      employeeIdPrefix: data['employeeIdPrefix'] as String? ?? 'OFX',
      nextEmployeeSeq: (data['nextEmployeeSeq'] as num?)?.toInt() ?? 1,
      ownerUid: data['ownerUid'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      workdayStartMinutes:
          (data['workdayStartMinutes'] as num?)?.toInt() ?? 9 * 60,
      officeLat: (data['officeLat'] as num?)?.toDouble(),
      officeLng: (data['officeLng'] as num?)?.toDouble(),
      geofenceMetres: (data['geofenceMetres'] as num?)?.toInt() ?? 0,
    );
  }
}

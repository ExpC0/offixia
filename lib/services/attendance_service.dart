import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/attendance.dart';
import '../models/employee.dart';
import '../models/organization.dart';
import 'db.dart';
import 'live.dart';
import 'location_service.dart';

/// Clocking in and out, and reading back who was where when.
class AttendanceService {
  AttendanceService._();

  static final AttendanceService instance = AttendanceService._();

  /// Today's record for one person, live. Watching a single known document id
  /// rather than running a query keeps this off the index list entirely.
  Stream<AttendanceRecord?> todayFor(String orgId, String uid) {
    final id = AttendanceRecord.idFor(
      uid,
      AttendanceRecord.dateKey(DateTime.now()),
    );
    return Db.attendance(orgId)
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? AttendanceRecord.fromDoc(doc) : null);
  }

  /// One person's history, newest first. `date` sorts lexicographically because
  /// it is a zero-padded `yyyy-MM-dd`, so this needs no separate sort field.
  Stream<List<AttendanceRecord>> historyFor(
    String orgId,
    String uid, {
    int limit = 60,
  }) {
    return Live.of('attendance/history/$orgId/$uid/$limit', () {
      return Db.attendance(orgId)
          .where('uid', isEqualTo: uid)
          .orderBy('date', descending: true)
          .limit(limit)
          .snapshots()
          .map((snap) => snap.docs.map(AttendanceRecord.fromDoc).toList());
    });
  }

  /// Everyone's records for a single day -- the manager and HR view.
  Stream<List<AttendanceRecord>> forDate(String orgId, DateTime day) {
    return Db.attendance(orgId)
        .where('date', isEqualTo: AttendanceRecord.dateKey(day))
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map(AttendanceRecord.fromDoc).toList()
                ..sort((a, b) => a.employeeName.compareTo(b.employeeName)),
        );
  }

  Future<void> checkIn({
    required Organization org,
    required Employee me,
  }) async {
    final fix = await _requireLocationWithinGeofence(org);
    final now = DateTime.now();
    final date = AttendanceRecord.dateKey(now);
    final ref = Db.attendance(org.id).doc(AttendanceRecord.idFor(me.uid, date));

    if ((await ref.get()).exists) {
      throw Exception('You have already checked in today.');
    }

    final minutesIntoDay = now.hour * 60 + now.minute;

    await ref.set({
      'uid': me.uid,
      'employeeName': me.name,
      'date': date,
      'checkInAt': FieldValue.serverTimestamp(),
      'checkInLat': fix?.latitude,
      'checkInLng': fix?.longitude,
      'late': minutesIntoDay > org.workdayStartMinutes,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> checkOut({
    required Organization org,
    required Employee me,
  }) async {
    final fix = await _requireLocationWithinGeofence(org);
    final date = AttendanceRecord.dateKey(DateTime.now());
    final ref = Db.attendance(org.id).doc(AttendanceRecord.idFor(me.uid, date));

    final existing = await ref.get();
    if (!existing.exists) {
      throw Exception('You have not checked in today.');
    }
    if (existing.data()?['checkOutAt'] != null) {
      throw Exception('You have already checked out today.');
    }

    await ref.update({
      'checkOutAt': FieldValue.serverTimestamp(),
      'checkOutLat': fix?.latitude,
      'checkOutLng': fix?.longitude,
    });
  }

  /// Returns the fix to stamp on the record, or null when the org has no
  /// geofence and location was unavailable.
  ///
  /// The distinction matters: with a geofence configured, no location means the
  /// punch must fail, because an unlocatable check-in would defeat the point.
  /// Without one, location is only a nice-to-have and must never be the reason
  /// somebody cannot record their day.
  Future<({double latitude, double longitude})?> _requireLocationWithinGeofence(
    Organization org,
  ) async {
    final result = await LocationService.instance.currentPosition();

    if (!result.ok) {
      if (org.hasGeofence) throw Exception(result.reason);
      return null;
    }

    final position = result.position!;
    if (org.hasGeofence) {
      final metres = LocationService.instance.metresBetween(
        fromLat: position.latitude,
        fromLng: position.longitude,
        toLat: org.officeLat!,
        toLng: org.officeLng!,
      );
      if (metres > org.geofenceMetres) {
        throw Exception(
          'You are ${metres.round()} m from the office, outside the '
          '${org.geofenceMetres} m check-in area.',
        );
      }
    }

    return (latitude: position.latitude, longitude: position.longitude);
  }
}

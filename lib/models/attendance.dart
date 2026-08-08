import 'package:cloud_firestore/cloud_firestore.dart';

/// One person's one day.
///
/// The document id is `{uid}_{yyyy-MM-dd}`, which makes "at most one record per
/// employee per day" a property of the database rather than something every
/// caller has to remember to check. Check-in creates the document; check-out
/// updates it.
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.uid,
    required this.employeeName,
    required this.date,
    this.checkInAt,
    this.checkOutAt,
    this.checkInLat,
    this.checkInLng,
    this.checkOutLat,
    this.checkOutLng,
    this.late = false,
  });

  final String id;
  final String uid;
  final String employeeName;

  /// `yyyy-MM-dd` in the device's local zone. Stored as a string because every
  /// query here is "this day" or "this month", and string prefixes sort and
  /// range-scan correctly without needing a composite index per timezone.
  final String date;

  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final double? checkInLat;
  final double? checkInLng;
  final double? checkOutLat;
  final double? checkOutLng;
  final bool late;

  bool get isOpen => checkInAt != null && checkOutAt == null;
  bool get isComplete => checkInAt != null && checkOutAt != null;

  /// Time on the clock. Still counting while the day is open, so the dashboard
  /// can show a running total.
  Duration get worked {
    final start = checkInAt;
    if (start == null) return Duration.zero;
    return (checkOutAt ?? DateTime.now()).difference(start);
  }

  static String idFor(String uid, String date) => '${uid}_$date';

  static String dateKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  factory AttendanceRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return AttendanceRecord(
      id: doc.id,
      uid: data['uid'] as String? ?? '',
      employeeName: data['employeeName'] as String? ?? '',
      date: data['date'] as String? ?? '',
      checkInAt: (data['checkInAt'] as Timestamp?)?.toDate(),
      checkOutAt: (data['checkOutAt'] as Timestamp?)?.toDate(),
      checkInLat: (data['checkInLat'] as num?)?.toDouble(),
      checkInLng: (data['checkInLng'] as num?)?.toDouble(),
      checkOutLat: (data['checkOutLat'] as num?)?.toDouble(),
      checkOutLng: (data['checkOutLng'] as num?)?.toDouble(),
      late: data['late'] as bool? ?? false,
    );
  }
}

import 'package:intl/intl.dart';

/// Date, time and duration formatting used across screens, kept together so
/// the app is consistent about how it writes a date.
class Fmt {
  Fmt._();

  static final _time = DateFormat.jm();
  static final _dayMonth = DateFormat('d MMM');
  static final _dayMonthYear = DateFormat('d MMM yyyy');
  static final _weekdayLong = DateFormat('EEEE, d MMMM');
  static final _monthYear = DateFormat('MMMM yyyy');

  static String time(DateTime? value) =>
      value == null ? '--:--' : _time.format(value);

  static String date(DateTime value) => _dayMonth.format(value);

  static String fullDate(DateTime value) => _dayMonthYear.format(value);

  static String longDate(DateTime value) => _weekdayLong.format(value);

  static String monthYear(DateTime value) => _monthYear.format(value);

  /// `7h 32m`, or `42m` when there is no hour to show. Zero reads as `--`
  /// rather than `0m`, so an empty cell is visibly empty.
  static String duration(Duration value) {
    if (value <= Duration.zero) return '--';
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    if (hours == 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }

  /// Minutes-past-midnight to a wall clock, for the org's workday start.
  static String minutesAsTime(int minutesPastMidnight) {
    final hour = minutesPastMidnight ~/ 60;
    final minute = minutesPastMidnight % 60;
    return _time.format(DateTime(2000, 1, 1, hour, minute));
  }

  /// Relative age for feed items: precise while it matters, then a plain date.
  static String relative(DateTime? value) {
    if (value == null) return '';
    final delta = DateTime.now().difference(value);
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    if (delta.inDays < 7) return '${delta.inDays}d ago';
    return _dayMonthYear.format(value);
  }

  /// A leave request's span, collapsing a single day to one date.
  static String dateRange(DateTime start, DateTime end) {
    if (start.year == end.year &&
        start.month == end.month &&
        start.day == end.day) {
      return _dayMonthYear.format(start);
    }
    if (start.year == end.year) {
      return '${_dayMonth.format(start)} - ${_dayMonthYear.format(end)}';
    }
    return '${_dayMonthYear.format(start)} - ${_dayMonthYear.format(end)}';
  }
}

import 'package:flutter/material.dart';

import '../format.dart';
import '../models/attendance.dart';
import '../models/employee.dart';
import '../models/organization.dart';
import '../services/attendance_service.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/punch_card.dart';
import '../widgets/ui.dart';

/// Your own attendance history, plus -- for managers and up -- a day view of
/// everyone else.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({
    super.key,
    required this.organization,
    required this.me,
  });

  final Organization organization;
  final Employee me;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _teamDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final showsTeam = widget.me.viewsAllAttendance;

    return DefaultTabController(
      length: showsTeam ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Attendance'),
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Me'),
              if (showsTeam) const Tab(text: 'Team'),
            ],
          ),
        ),
        body: TabBarView(children: [_myTab(), if (showsTeam) _teamTab()]),
      ),
    );
  }

  Widget _myTab() {
    return StreamBuilder<List<AttendanceRecord>>(
      stream: AttendanceService.instance.historyFor(
        widget.organization.id,
        widget.me.uid,
      ),
      builder: (context, snapshot) {
        final records = snapshot.data ?? const <AttendanceRecord>[];

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            PunchCard(organization: widget.organization, me: widget.me),
            const SizedBox(height: 20),
            if (records.isNotEmpty) _monthSummary(records),
            const SizedBox(height: 12),
            const Text(
              'History',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (snapshot.hasError)
              const _Muted('Could not load your history.')
            else if (snapshot.connectionState == ConnectionState.waiting)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (records.isEmpty)
              const _Muted('No days recorded yet. Check in to start.')
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < records.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, indent: 16, endIndent: 16),
                      _HistoryRow(record: records[i]),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  /// A quick month total from the records already on screen. Deliberately not
  /// a separate aggregate query -- the history stream is capped at 60 days, so
  /// everything needed is in memory already.
  Widget _monthSummary(List<AttendanceRecord> records) {
    final now = DateTime.now();
    final prefix =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';
    final thisMonth = records.where((r) => r.date.startsWith(prefix)).toList();

    final worked = thisMonth.fold(
      Duration.zero,
      (total, record) =>
          total + (record.isComplete ? record.worked : Duration.zero),
    );
    final lateCount = thisMonth.where((r) => r.late).length;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              child: _Summary(
                label: Fmt.monthYear(now),
                value: '${thisMonth.length}',
                caption: 'days',
              ),
            ),
            Expanded(
              child: _Summary(
                label: 'Hours',
                value: Fmt.duration(worked),
                caption: 'this month',
              ),
            ),
            Expanded(
              child: _Summary(
                label: 'Late',
                value: '$lateCount',
                caption: lateCount == 1 ? 'day' : 'days',
                color: lateCount > 0 ? AppSurfaces.of(context).caution : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(
                  () => _teamDay = _teamDay.subtract(const Duration(days: 1)),
                ),
              ),
              Expanded(
                child: Text(
                  Fmt.longDate(_teamDay),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                // Tomorrow has no attendance to show, so stop at today.
                onPressed: _isToday(_teamDay)
                    ? null
                    : () => setState(
                        () => _teamDay = _teamDay.add(const Duration(days: 1)),
                      ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<AttendanceRecord>>(
            stream: AttendanceService.instance.forDate(
              widget.organization.id,
              _teamDay,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const ErrorState(
                  message: 'Could not load the team\'s attendance.',
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final records = snapshot.data ?? const <AttendanceRecord>[];
              if (records.isEmpty) {
                return const EmptyState(
                  icon: Icons.event_busy_outlined,
                  title: 'Nobody checked in',
                  message: 'No attendance was recorded on this day.',
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: records.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final record = records[index];
                  return AppCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      title: Text(
                        record.employeeName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${Fmt.time(record.checkInAt)} - '
                        '${Fmt.time(record.checkOutAt)}',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            Fmt.duration(record.worked),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (record.late)
                            Text(
                              'Late',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppSurfaces.of(context).caution,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.record});

  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: record.late
            ? AppSurfaces.of(context).caution.withValues(alpha: 0.15)
            : AppSurfaces.of(context).positive.withValues(alpha: 0.15),
        child: Icon(
          record.late ? Icons.running_with_errors : Icons.check,
          size: 18,
          color: record.late
              ? AppSurfaces.of(context).caution
              : AppSurfaces.of(context).positive,
        ),
      ),
      title: Text(
        record.date,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${Fmt.time(record.checkInAt)} - ${Fmt.time(record.checkOutAt)}',
      ),
      trailing: Text(
        Fmt.duration(record.isComplete ? record.worked : Duration.zero),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.label,
    required this.value,
    required this.caption,
    this.color,
  });

  final String label;
  final String value;
  final String caption;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          caption,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

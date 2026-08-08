import 'dart:async';

import 'package:flutter/material.dart';

import '../format.dart';
import '../models/attendance.dart';
import '../models/employee.dart';
import '../models/organization.dart';
import '../services/attendance_service.dart';
import '../theme.dart';

/// The hero of the app: today's clock, and the one button that changes it.
///
/// Rendered on the brand gradient rather than a plain card, because it is the
/// single thing most people open Offixia to do and everything else on the
/// dashboard is secondary to it.
class PunchCard extends StatefulWidget {
  const PunchCard({super.key, required this.organization, required this.me});

  final Organization organization;
  final Employee me;

  @override
  State<PunchCard> createState() => _PunchCardState();
}

class _PunchCardState extends State<PunchCard> {
  late final Stream<AttendanceRecord?> _today;
  Timer? _ticker;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _today = AttendanceService.instance.todayFor(
      widget.organization.id,
      widget.me.uid,
    );
    // "So far" is computed from the wall clock, not from a document change,
    // so nothing would repaint it without a timer of its own.
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _punch(AttendanceRecord? record) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (record == null) {
        await AttendanceService.instance.checkIn(
          org: widget.organization,
          me: widget.me,
        );
        messenger.showSnackBar(
          const SnackBar(content: Text('Checked in. Have a good day.')),
        );
      } else {
        await AttendanceService.instance.checkOut(
          org: widget.organization,
          me: widget.me,
        );
        messenger.showSnackBar(
          const SnackBar(content: Text('Checked out. See you tomorrow.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.negative,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);

    return StreamBuilder<AttendanceRecord?>(
      stream: _today,
      builder: (context, snapshot) {
        final record = snapshot.data;
        final complete = record?.isComplete ?? false;
        final open = record?.isOpen ?? false;

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: surfaces.heroGradient,
            ),
            boxShadow: [
              BoxShadow(
                color: surfaces.heroGradient.last.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
                spreadRadius: -8,
              ),
            ],
          ),
          child: Stack(
            children: [
              // A soft highlight so the gradient reads as a lit surface
              // rather than a flat fill.
              Positioned(
                right: -40,
                top: -50,
                child: Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.today_rounded,
                          size: 15,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          Fmt.longDate(DateTime.now()),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        const Spacer(),
                        if (record?.late == true)
                          _HeroTag(
                            text: 'Late',
                            icon: Icons.running_with_errors_rounded,
                          )
                        else if (complete)
                          _HeroTag(
                            text: 'Complete',
                            icon: Icons.check_circle_rounded,
                          )
                        else if (open)
                          _HeroTag(
                            text: 'On the clock',
                            icon: Icons.bolt_rounded,
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                complete ? 'Hours worked' : 'Time on the clock',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.75),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                Fmt.duration(record?.worked ?? Duration.zero),
                                style: const TextStyle(
                                  fontSize: 36,
                                  height: 1.1,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -1.5,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _HeroTime(
                          label: 'In',
                          value: Fmt.time(record?.checkInAt),
                        ),
                        const SizedBox(width: 18),
                        _HeroTime(
                          label: 'Out',
                          value: Fmt.time(record?.checkOutAt),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: complete
                          ? _DoneBar()
                          : _PunchButton(
                              busy: _busy,
                              checkingOut: record != null,
                              onPressed: () => _punch(record),
                            ),
                    ),
                    if (widget.organization.hasGeofence) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            size: 13,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Within ${widget.organization.geofenceMetres} m of '
                            'the office',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PunchButton extends StatelessWidget {
  const _PunchButton({
    required this.busy,
    required this.checkingOut,
    required this.onPressed,
  });

  final bool busy;
  final bool checkingOut;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tint = checkingOut ? const Color(0xFFFFD9D9) : Colors.white;

    return FilledButton.icon(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: tint,
        foregroundColor: checkingOut
            ? const Color(0xFF9B1C1C)
            : AppTheme.seedDeep,
        disabledBackgroundColor: tint.withValues(alpha: 0.6),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: busy
          ? SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: checkingOut
                    ? const Color(0xFF9B1C1C)
                    : AppTheme.seedDeep,
              ),
            )
          : Icon(
              checkingOut ? Icons.logout_rounded : Icons.login_rounded,
              size: 19,
            ),
      label: Text(
        busy ? 'Just a moment...' : (checkingOut ? 'Check out' : 'Check in'),
        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _DoneBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.verified_rounded, size: 18, color: Colors.white),
          const SizedBox(width: 9),
          Text(
            'Day complete',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroTime extends StatelessWidget {
  const _HeroTime({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

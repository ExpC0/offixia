import 'package:flutter/material.dart';

import '../models/leave_request.dart';
import '../models/role.dart';
import '../models/work_task.dart';
import '../theme.dart';

/// A small tinted label. One widget for every status in the app, so approved
/// leave and a finished task read as the same kind of thing.
///
/// Colour comes from [AppSurfaces] rather than raw constants, because the
/// light-theme status palette goes muddy on a near-black surface and needs its
/// lifted twin instead.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.icon,
    this.tone = StatusTone.neutral,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final StatusTone tone;
  final bool dense;

  factory StatusChip.leave(LeaveStatus status) => StatusChip(
    label: status.label,
    tone: switch (status) {
      LeaveStatus.pending => StatusTone.caution,
      LeaveStatus.approved => StatusTone.positive,
      LeaveStatus.rejected => StatusTone.negative,
      LeaveStatus.cancelled => StatusTone.neutral,
    },
    icon: switch (status) {
      LeaveStatus.pending => Icons.schedule_rounded,
      LeaveStatus.approved => Icons.check_circle_rounded,
      LeaveStatus.rejected => Icons.cancel_rounded,
      LeaveStatus.cancelled => Icons.remove_circle_outline_rounded,
    },
  );

  factory StatusChip.task(TaskStatus status) => StatusChip(
    label: status.label,
    tone: switch (status) {
      TaskStatus.todo => StatusTone.neutral,
      TaskStatus.inProgress => StatusTone.brand,
      TaskStatus.done => StatusTone.positive,
    },
  );

  factory StatusChip.priority(TaskPriority priority) => StatusChip(
    label: priority.label,
    dense: true,
    tone: switch (priority) {
      TaskPriority.low => StatusTone.neutral,
      TaskPriority.normal => StatusTone.brand,
      TaskPriority.high => StatusTone.caution,
      TaskPriority.urgent => StatusTone.negative,
    },
  );

  /// Seniority reads as heat: the further up the ladder, the warmer.
  factory StatusChip.role(Role role) => StatusChip(
    label: role.label,
    dense: true,
    tone: switch (role) {
      Role.employee => StatusTone.neutral,
      Role.manager => StatusTone.brand,
      Role.hr => StatusTone.violet,
      Role.dgm => StatusTone.caution,
      Role.gm => StatusTone.caution,
      Role.md => StatusTone.negative,
    },
  );

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);
    final scheme = Theme.of(context).colorScheme;

    final color = switch (tone) {
      StatusTone.positive => surfaces.positive,
      StatusTone.caution => surfaces.caution,
      StatusTone.negative => surfaces.negative,
      StatusTone.brand => scheme.primary,
      StatusTone.violet => const Color(0xFF9B7DEA),
      StatusTone.neutral => scheme.onSurfaceVariant,
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12.5, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 11 : 11.5,
              fontWeight: FontWeight.w700,
              height: 1.1,
              color: color,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

enum StatusTone { positive, caution, negative, brand, violet, neutral }

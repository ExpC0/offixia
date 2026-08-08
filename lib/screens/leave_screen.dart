import 'package:flutter/material.dart';

import '../format.dart';
import '../models/employee.dart';
import '../models/leave_request.dart';
import '../models/organization.dart';
import '../services/leave_service.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_chip.dart';
import '../widgets/ui.dart';
import 'approvals_screen.dart';
import 'leave_request_screen.dart';

/// Your time off: what you have asked for and where each request stands.
class LeaveScreen extends StatelessWidget {
  const LeaveScreen({super.key, required this.organization, required this.me});

  final Organization organization;
  final Employee me;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leave'),
        actions: [
          if (me.approvesSomeLeave)
            IconButton(
              tooltip: 'Approvals',
              icon: const Icon(Icons.how_to_reg_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ApprovalsScreen(organization: organization, me: me),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                LeaveRequestScreen(organization: organization, me: me),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Request'),
      ),
      body: StreamBuilder<List<LeaveRequest>>(
        stream: LeaveService.instance.myRequests(organization.id, me.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ErrorState(message: 'Could not load your requests.');
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final requests = snapshot.data ?? const <LeaveRequest>[];
          if (requests.isEmpty) {
            return const EmptyState(
              icon: Icons.beach_access_outlined,
              title: 'No leave requested',
              message: 'Tap Request to ask for time off.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: requests.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _LeaveCard(
              organization: organization,
              request: requests[index],
            ),
          );
        },
      ),
    );
  }
}

class _LeaveCard extends StatelessWidget {
  const _LeaveCard({required this.organization, required this.request});

  final Organization organization;
  final LeaveRequest request;

  Future<void> _cancel(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final negative = AppSurfaces.of(context).negative;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: const Text(
          'It will be withdrawn and your approver will no longer see it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await LeaveService.instance.cancel(
        orgId: organization.id,
        request: request,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: negative,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.type.label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                StatusChip.leave(request.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${Fmt.dateRange(request.startDate, request.endDate)}  ·  '
              '${request.days} ${request.days == 1 ? 'day' : 'days'}',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            if (request.reason.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(request.reason, style: const TextStyle(fontSize: 13.5)),
            ],
            if (request.decidedByName != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${request.status.label} by ${request.decidedByName}'
                      '${request.decidedAt == null ? '' : ' · ${Fmt.relative(request.decidedAt)}'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (request.decisionNote.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        request.decisionNote,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (request.isPending) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _cancel(context),
                  child: const Text('Cancel request'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

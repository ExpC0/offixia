import 'package:flutter/material.dart';

import '../format.dart';
import '../models/employee.dart';
import '../models/leave_request.dart';
import '../models/organization.dart';
import '../services/leave_service.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/ui.dart';

/// The approver's queue. A manager sees their own reports; HR and the owner
/// see everyone.
class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({
    super.key,
    required this.organization,
    required this.me,
  });

  final Organization organization;
  final Employee me;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Approvals'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                me.approvesAnyLeave
                    ? 'All pending requests in ${organization.name}'
                    : 'Pending requests from your team',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<LeaveRequest>>(
        stream: LeaveService.instance.pendingFor(organization.id, me),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ErrorState(message: 'Could not load the queue.');
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final requests = snapshot.data ?? const <LeaveRequest>[];
          if (requests.isEmpty) {
            return const EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Nothing to approve',
              message: 'Every request has been dealt with.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: requests.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _ApprovalCard(
              organization: organization,
              me: me,
              request: requests[index],
            ),
          );
        },
      ),
    );
  }
}

class _ApprovalCard extends StatefulWidget {
  const _ApprovalCard({
    required this.organization,
    required this.me,
    required this.request,
  });

  final Organization organization;
  final Employee me;
  final LeaveRequest request;

  @override
  State<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<_ApprovalCard> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    final note = await _askForNote(approve);
    // A null note means the sheet was dismissed -- not the same as an empty
    // note, which means "decide, but say nothing".
    if (note == null) return;
    if (!mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final negative = AppSurfaces.of(context).negative;
    try {
      await LeaveService.instance.decide(
        orgId: widget.organization.id,
        request: widget.request,
        decidedBy: widget.me,
        approve: approve,
        note: note,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? 'Approved ${widget.request.employeeName}\'s leave.'
                : 'Rejected ${widget.request.employeeName}\'s leave.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: negative,
        ),
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askForNote(bool approve) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Approve leave' : 'Reject leave'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.request.employeeName} · '
              '${Fmt.dateRange(widget.request.startDate, widget.request.endDate)}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Add a note (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back'),
          ),
          FilledButton(
            style: approve
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: AppSurfaces.of(context).negative,
                  ),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              request.employeeName,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${request.type.label} · ${request.days} '
              '${request.days == 1 ? 'day' : 'days'}',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Text(
              Fmt.dateRange(request.startDate, request.endDate),
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (request.reason.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(request.reason, style: const TextStyle(fontSize: 13.5)),
            ],
            const SizedBox(height: 6),
            Text(
              'Requested ${Fmt.relative(request.createdAt)}',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            // Mirrors the security rule. Offering buttons the server will
            // refuse is what turned "you cannot sign off your own leave" into
            // an unexplained permission-denied.
            if (!widget.me.canDecide(
              requesterUid: request.uid,
              managerUid: request.managerUid,
              ownerUid: widget.organization.ownerUid,
            ))
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        request.uid == widget.me.uid
                            ? 'You cannot approve your own leave. This goes to '
                                  'whoever is above you.'
                            : 'Only this person\'s manager, HR or above can '
                                  'decide this.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _decide(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppSurfaces.of(context).negative,
                      ),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _decide(true),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Approve'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

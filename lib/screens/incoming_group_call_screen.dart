import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/employee.dart';
import '../models/group_call.dart';
import '../models/organization.dart';
import '../services/call_tone_service.dart';
import '../services/employee_service.dart';
import '../services/group_call_service.dart';
import '../theme.dart';
import 'group_call_screen.dart';

class IncomingGroupCallScreen extends StatefulWidget {
  const IncomingGroupCallScreen({
    super.key,
    required this.organization,
    required this.me,
    required this.call,
  });

  final Organization organization;
  final Employee me;
  final GroupCall call;

  @override
  State<IncomingGroupCallScreen> createState() =>
      _IncomingGroupCallScreenState();
}

class _IncomingGroupCallScreenState extends State<IncomingGroupCallScreen> {
  late final Stream<GroupCall?> _call;
  bool _busy = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _call = GroupCallService.instance.watch(
      widget.organization.id,
      widget.call.id,
    );
    unawaited(CallToneService.incoming());
  }

  @override
  void dispose() {
    unawaited(CallToneService.stop());
    super.dispose();
  }

  Future<void> _answer() async {
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await CallToneService.stop();
    final permissions = await <Permission>[
      Permission.microphone,
      if (widget.call.isVideo) Permission.camera,
    ].request();
    if (!permissions.values.every((status) => status.isGranted)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Microphone and camera access needed.')),
      );
      if (mounted) setState(() => _busy = false);
      return;
    }

    try {
      final people = await EmployeeService.instance
          .directory(widget.organization.id)
          .first;
      await GroupCallService.instance.answer(
        orgId: widget.organization.id,
        call: widget.call,
        me: widget.me,
      );
      _leaving = true;
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => GroupCallScreen(
            organization: widget.organization,
            me: widget.me,
            callId: widget.call.id,
            groupName: widget.call.groupName,
            isVideo: widget.call.isVideo,
            outgoing: false,
            names: {for (final person in people) person.uid: person.name},
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.negative,
        ),
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    await CallToneService.stop();
    try {
      await GroupCallService.instance.decline(
        orgId: widget.organization.id,
        call: widget.call,
        uid: widget.me.uid,
      );
    } finally {
      if (mounted && !_leaving) {
        _leaving = true;
        navigator.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<GroupCall?>(
    stream: _call,
    builder: (context, snapshot) {
      final call = snapshot.data;
      final resolved = snapshot.connectionState != ConnectionState.waiting;
      if (resolved &&
          (call == null || call.isEnded || !call.isRingingFor(widget.me.uid))) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_busy && !_leaving) {
            _leaving = true;
            Navigator.of(context).pop();
          }
        });
      }
      return PopScope(
        canPop: true,
        child: Scaffold(
          backgroundColor: const Color(0xFF0B0D12),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 34),
              child: Column(
                children: [
                  const Spacer(),
                  const CircleAvatar(
                    radius: 58,
                    backgroundColor: Colors.white12,
                    child: Icon(
                      Icons.groups_rounded,
                      size: 52,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.call.groupName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.call.callerName} started a group ${widget.call.isVideo ? 'video' : 'audio'} call',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded, size: 14, color: Colors.white60),
                      SizedBox(width: 5),
                      Text(
                        'End-to-end encrypted mesh',
                        style: TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _IncomingButton(
                        icon: Icons.call_end_rounded,
                        label: 'Decline',
                        color: AppTheme.negative,
                        onTap: _busy ? null : _decline,
                      ),
                      _IncomingButton(
                        icon: widget.call.isVideo
                            ? Icons.videocam_rounded
                            : Icons.call_rounded,
                        label: 'Join',
                        color: AppTheme.positive,
                        onTap: _busy ? null : _answer,
                      ),
                    ],
                  ),
                  const SizedBox(height: 46),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _IncomingButton extends StatelessWidget {
  const _IncomingButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(21),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: Colors.white70)),
    ],
  );
}

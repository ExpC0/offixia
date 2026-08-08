import 'dart:async';

import 'package:flutter/material.dart';

import '../models/call.dart';
import '../models/employee.dart';
import '../models/organization.dart';
import '../services/call_service.dart';
import '../services/call_tone_service.dart';
import '../services/calls.dart';
import '../theme.dart';

/// The ringing screen.
///
/// Shown over whatever the person was doing, because a call cannot wait for
/// them to navigate somewhere. It stays up only while the call document says
/// `ringing`: if the caller gives up, the screen closes itself.
class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({
    super.key,
    required this.organization,
    required this.me,
    required this.call,
  });

  final Organization organization;
  final Employee me;
  final Call call;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  late final Stream<Call?> _call;
  bool _busy = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _call = CallService.instance.watch(widget.organization.id, widget.call.id);
    unawaited(CallToneService.incoming());
  }

  @override
  void dispose() {
    unawaited(CallToneService.stop());
    super.dispose();
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await CallToneService.stop();

    try {
      final granted = await Calls.ensurePermissions(video: widget.call.isVideo);
      if (!granted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Microphone and camera access are needed to answer.'),
          ),
        );
        if (mounted) setState(() => _busy = false);
        return;
      }

      await CallService.instance.answer(
        orgId: widget.organization.id,
        call: widget.call,
      );

      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => CallScreenRoute(
            organization: widget.organization,
            me: widget.me,
            callId: widget.call.id,
            otherName: widget.call.callerName,
            isVideo: widget.call.isVideo,
            outgoing: false,
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
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    await CallToneService.stop();
    try {
      await CallService.instance.decline(
        orgId: widget.organization.id,
        call: widget.call,
      );
    } finally {
      if (mounted && !_leaving) {
        _leaving = true;
        navigator.pop();
      }
    }
  }

  void _dismissEndedCall() {
    if (!mounted || _busy || _leaving) return;
    _leaving = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Call?>(
      stream: _call,
      builder: (context, snapshot) {
        final call = snapshot.data;

        // The initial frame has no data while Firestore is still connecting;
        // that is not an ended call. Wait for the first resolved snapshot.
        final resolved = snapshot.connectionState != ConnectionState.waiting;
        if (resolved && (call == null || call.status != CallStatus.ringing)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _dismissEndedCall();
          });
        }

        final initial = widget.call.callerName.trim().isEmpty
            ? '?'
            : widget.call.callerName.trim()[0].toUpperCase();

        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop && !_busy && !_leaving) {
              _leaving = true;
              unawaited(CallToneService.stop());
              unawaited(
                CallService.instance.decline(
                  orgId: widget.organization.id,
                  call: widget.call,
                ),
              );
            }
          },
          child: Scaffold(
            backgroundColor: const Color(0xFF0B0D12),
            body: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF243056), Color(0xFF0B0D12)],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    const Spacer(),
                    Container(
                      width: 116,
                      height: 116,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      widget.call.callerName,
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Incoming ${widget.call.isVideo ? 'video' : 'audio'} call',
                      style: TextStyle(
                        fontSize: 14.5,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          size: 13,
                          color: Colors.white.withValues(alpha: 0.58),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'End-to-end encrypted',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.62),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(40, 0, 40, 46),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _RingButton(
                            icon: Icons.call_end_rounded,
                            color: AppTheme.negative,
                            label: 'Decline',
                            onTap: _busy ? null : _decline,
                          ),
                          _RingButton(
                            icon: widget.call.isVideo
                                ? Icons.videocam_rounded
                                : Icons.call_rounded,
                            color: AppTheme.positive,
                            label: 'Answer',
                            onTap: _busy ? null : _accept,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingButton extends StatelessWidget {
  const _RingButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(21),
              child: Icon(icon, size: 31, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

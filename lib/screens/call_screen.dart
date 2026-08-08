import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/call.dart';
import '../models/employee.dart';
import '../models/organization.dart';
import '../services/call_service.dart';
import '../services/call_tone_service.dart';
import '../theme.dart';

/// A call in progress.
///
/// Always full screen and always on top: a call is the one thing in this app
/// that owns the whole device while it lasts.
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.organization,
    required this.me,
    required this.callId,
    required this.otherName,
    required this.isVideo,
    this.outgoing = true,
  });

  final Organization organization;
  final Employee me;
  final String callId;
  final String otherName;
  final bool isVideo;

  /// Whether this phone placed the call. Only changes the wording while it
  /// rings; everything after that is symmetrical.
  final bool outgoing;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _remoteRenderer = RTCVideoRenderer();
  final _localRenderer = RTCVideoRenderer();

  late final Stream<Call?> _call;
  Timer? _ticker;
  DateTime? _connectedAt;

  bool _muted = false;
  bool _cameraOn = true;
  bool _speakerOn = false;
  bool _ready = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _call = CallService.instance.watch(widget.organization.id, widget.callId);
    _speakerOn = widget.isVideo;
    unawaited(_prepare());
    if (widget.outgoing) unawaited(CallToneService.outgoing());

    CallService.instance.remoteStream.addListener(_attachRemote);
    CallService.instance.localStream.addListener(_attachLocal);

    // Drives the call duration, which is wall-clock rather than
    // document-driven and so would never repaint on its own.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _connectedAt != null) setState(() {});
    });
  }

  Future<void> _prepare() async {
    await _remoteRenderer.initialize();
    await _localRenderer.initialize();
    await CallService.instance.setSpeaker(widget.isVideo);
    if (!mounted) return;
    setState(() => _ready = true);
    _attachRemote();
    _attachLocal();
  }

  void _attachRemote() {
    if (!_ready) return;
    _remoteRenderer.srcObject = CallService.instance.remoteStream.value;
    if (mounted) setState(() {});
  }

  void _attachLocal() {
    if (!_ready) return;
    _localRenderer.srcObject = CallService.instance.localStream.value;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(CallToneService.stop());
    _ticker?.cancel();
    CallService.instance.remoteStream.removeListener(_attachRemote);
    CallService.instance.localStream.removeListener(_attachLocal);
    _remoteRenderer.dispose();
    _localRenderer.dispose();
    super.dispose();
  }

  void _hangUp() {
    if (_leaving) return;
    unawaited(
      CallService.instance.hangUp(
        orgId: widget.organization.id,
        callId: widget.callId,
      ),
    );
    _requestExit();
  }

  void _requestExit() {
    if (!mounted || _leaving) return;
    _leaving = true;
    // A call route must dismiss locally without waiting for Firestore or
    // WebRTC teardown. `maybePop` can legitimately refuse a pop depending on
    // navigator state, which previously left the user trapped here.
    Navigator.of(context).pop();
  }

  String get _elapsed {
    final started = _connectedAt;
    if (started == null) return '';
    final seconds = DateTime.now().difference(started).inSeconds;
    final minutes = seconds ~/ 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Call?>(
      stream: _call,
      builder: (context, snapshot) {
        final call = snapshot.data;

        // The other side hanging up, declining, or the document disappearing
        // all end this screen. Popping from a post-frame callback keeps the
        // navigation out of the build phase.
        final resolved = snapshot.connectionState != ConnectionState.waiting;
        if (resolved && (call == null || call.status.isOver)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _requestExit();
          });
        }

        if (call?.status == CallStatus.active && _connectedAt == null) {
          _connectedAt = call?.answeredAt ?? DateTime.now();
          unawaited(CallToneService.stop());
        }

        final connected = call?.status == CallStatus.active;
        final hasRemoteVideo =
            widget.isVideo && _remoteRenderer.srcObject != null;

        return PopScope(
          // Allow the route to close immediately. If the system back gesture
          // closed it rather than the red button, end media in the callback.
          canPop: true,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop && !_leaving) {
              _leaving = true;
              unawaited(
                CallService.instance.hangUp(
                  orgId: widget.organization.id,
                  callId: widget.callId,
                ),
              );
            }
          },
          child: Scaffold(
            backgroundColor: const Color(0xFF0B0D12),
            body: Stack(
              fit: StackFit.expand,
              children: [
                if (hasRemoteVideo)
                  RTCVideoView(
                    _remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                else
                  _AudioBackdrop(
                    name: widget.otherName,
                    status: _statusLine(call, connected),
                  ),

                if (widget.isVideo && _localRenderer.srcObject != null)
                  Positioned(
                    right: 16,
                    top: MediaQuery.of(context).padding.top + 16,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 104,
                        height: 150,
                        child: RTCVideoView(
                          _localRenderer,
                          mirror: true,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                      ),
                    ),
                  ),

                if (hasRemoteVideo)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: MediaQuery.of(context).padding.top + 16,
                    child: Column(
                      children: [
                        Text(
                          widget.otherName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          _statusLine(call, connected),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const _EncryptionBadge(),
                      ],
                    ),
                  ),

                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _Controls(
                    isVideo: widget.isVideo,
                    muted: _muted,
                    cameraOn: _cameraOn,
                    speakerOn: _speakerOn,
                    onMute: () {
                      setState(() => _muted = !_muted);
                      CallService.instance.toggleMute(_muted);
                    },
                    onCamera: () {
                      setState(() => _cameraOn = !_cameraOn);
                      CallService.instance.toggleCamera(_cameraOn);
                    },
                    onSpeaker: () {
                      setState(() => _speakerOn = !_speakerOn);
                      unawaited(CallService.instance.setSpeaker(_speakerOn));
                    },
                    onSwitchCamera: () =>
                        unawaited(CallService.instance.switchCamera()),
                    onHangUp: _hangUp,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _statusLine(Call? call, bool connected) {
    if (call == null) return 'Ending';
    if (connected) return _elapsed.isEmpty ? 'Connected' : _elapsed;
    return widget.outgoing ? 'Ringing...' : 'Connecting...';
  }
}

/// What fills the screen on an audio call, or before video arrives.
class _AudioBackdrop extends StatelessWidget {
  const _AudioBackdrop({required this.name, required this.status});

  final String name;
  final String status;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3447A6), Color(0xFF182044), Color(0xFF090B11)],
          stops: [0, 0.48, 1],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 150,
            height: 150,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
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
          ),
          const SizedBox(height: 28),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.82),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const _EncryptionBadge(),
        ],
      ),
    );
  }
}

class _EncryptionBadge extends StatelessWidget {
  const _EncryptionBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
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
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.isVideo,
    required this.muted,
    required this.cameraOn,
    required this.speakerOn,
    required this.onMute,
    required this.onCamera,
    required this.onSpeaker,
    required this.onSwitchCamera,
    required this.onHangUp,
  });

  final bool isVideo;
  final bool muted;
  final bool cameraOn;
  final bool speakerOn;
  final VoidCallback onMute;
  final VoidCallback onCamera;
  final VoidCallback onSpeaker;
  final VoidCallback onSwitchCamera;
  final VoidCallback onHangUp;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
        decoration: BoxDecoration(
          color: const Color(0xFF171A22).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _CallButton(
              icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
              active: muted,
              label: 'Mute',
              onTap: onMute,
            ),
            if (isVideo)
              _CallButton(
                icon: cameraOn
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_rounded,
                active: !cameraOn,
                label: 'Camera',
                onTap: onCamera,
              )
            else
              _CallButton(
                icon: speakerOn
                    ? Icons.volume_up_rounded
                    : Icons.hearing_rounded,
                active: speakerOn,
                label: 'Speaker',
                onTap: onSpeaker,
              ),
            if (isVideo)
              _CallButton(
                icon: Icons.cameraswitch_rounded,
                label: 'Flip',
                onTap: onSwitchCamera,
              ),
            _CallButton(
              icon: Icons.call_end_rounded,
              label: 'End',
              background: AppTheme.negative,
              foreground: Colors.white,
              onTap: onHangUp,
            ),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final fill =
        background ??
        (active
            ? Colors.white.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.14));
    final tint =
        foreground ?? (active ? const Color(0xFF0B0D12) : Colors.white);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: fill,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Icon(icon, size: 25, color: tint),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}

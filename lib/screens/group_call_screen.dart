import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/group_call.dart';
import '../models/employee.dart';
import '../models/organization.dart';
import '../services/call_tone_service.dart';
import '../services/group_call_service.dart';
import '../theme.dart';

class GroupCallScreen extends StatefulWidget {
  const GroupCallScreen({
    super.key,
    required this.organization,
    required this.me,
    required this.callId,
    required this.groupName,
    required this.isVideo,
    required this.names,
    this.outgoing = true,
  });

  final Organization organization;
  final Employee me;
  final String callId;
  final String groupName;
  final bool isVideo;
  final Map<String, String> names;
  final bool outgoing;

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  late final Stream<GroupCall?> _call;
  bool _ready = false;
  bool _muted = false;
  bool _cameraOn = true;
  late bool _speakerOn;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _speakerOn = widget.isVideo;
    _call = GroupCallService.instance.watch(
      widget.organization.id,
      widget.callId,
    );
    if (widget.outgoing) unawaited(CallToneService.outgoing());
    GroupCallService.instance.localStream.addListener(_syncStreams);
    GroupCallService.instance.remoteStreams.addListener(_syncStreams);
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    await _localRenderer.initialize();
    _localRenderer.srcObject = GroupCallService.instance.localStream.value;
    await GroupCallService.instance.setSpeaker(_speakerOn);
    if (!mounted) return;
    setState(() => _ready = true);
    _syncStreams();
  }

  void _syncStreams() {
    if (!_ready) return;
    _localRenderer.srcObject = GroupCallService.instance.localStream.value;
    final streams = GroupCallService.instance.remoteStreams.value;
    for (final entry in streams.entries) {
      if (_remoteRenderers.containsKey(entry.key)) {
        _remoteRenderers[entry.key]!.srcObject = entry.value;
        continue;
      }
      final renderer = RTCVideoRenderer();
      _remoteRenderers[entry.key] = renderer;
      unawaited(
        renderer.initialize().then((_) {
          renderer.srcObject = entry.value;
          if (mounted) setState(() {});
        }),
      );
    }
    for (final uid
        in _remoteRenderers.keys
            .where((uid) => !streams.containsKey(uid))
            .toList()) {
      final renderer = _remoteRenderers.remove(uid)!;
      unawaited(renderer.dispose());
    }
    if (mounted) setState(() {});
  }

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    unawaited(
      GroupCallService.instance.leave(
        orgId: widget.organization.id,
        callId: widget.callId,
        uid: widget.me.uid,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    unawaited(CallToneService.stop());
    GroupCallService.instance.localStream.removeListener(_syncStreams);
    GroupCallService.instance.remoteStreams.removeListener(_syncStreams);
    unawaited(_localRenderer.dispose());
    for (final renderer in _remoteRenderers.values) {
      unawaited(renderer.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GroupCall?>(
      stream: _call,
      builder: (context, snapshot) {
        final call = snapshot.data;
        final resolved = snapshot.connectionState != ConnectionState.waiting;
        if (call?.joinedUids.length case final count? when count > 1) {
          unawaited(CallToneService.stop());
        }
        if (resolved && (call == null || call.isEnded)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_leaving) {
              _leaving = true;
              Navigator.of(context).pop();
            }
          });
        }

        final joined = call?.joinedUids ?? [widget.me.uid];
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop && !_leaving) {
              _leaving = true;
              unawaited(
                GroupCallService.instance.leave(
                  orgId: widget.organization.id,
                  callId: widget.callId,
                  uid: widget.me.uid,
                ),
              );
            }
          },
          child: Scaffold(
            backgroundColor: const Color(0xFF090B12),
            body: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                    child: Column(
                      children: [
                        Text(
                          widget.groupName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${joined.length} of ${call?.invitedUids.length ?? 1} joined',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .62),
                          ),
                        ),
                        const SizedBox(height: 7),
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_rounded,
                              size: 13,
                              color: Colors.white60,
                            ),
                            SizedBox(width: 5),
                            Text(
                              'End-to-end encrypted mesh',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(10),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: joined.length <= 1 ? 1 : 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: joined.length == 2 ? .78 : .86,
                      ),
                      itemCount: joined.length,
                      itemBuilder: (context, index) {
                        final uid = joined[index];
                        final mine = uid == widget.me.uid;
                        return _ParticipantTile(
                          name: mine
                              ? '${widget.me.name} (You)'
                              : widget.names[uid] ?? 'Participant',
                          renderer: mine
                              ? _localRenderer
                              : _remoteRenderers[uid],
                          showVideo:
                              widget.isVideo &&
                              (mine
                                  ? _cameraOn
                                  : _remoteRenderers[uid] != null),
                          mirror: mine,
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _GroupControl(
                          icon: _muted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                          active: _muted,
                          onTap: () {
                            setState(() => _muted = !_muted);
                            GroupCallService.instance.toggleMute(_muted);
                          },
                        ),
                        _GroupControl(
                          icon: _speakerOn
                              ? Icons.volume_up_rounded
                              : Icons.hearing_rounded,
                          active: _speakerOn,
                          onTap: () {
                            setState(() => _speakerOn = !_speakerOn);
                            unawaited(
                              GroupCallService.instance.setSpeaker(_speakerOn),
                            );
                          },
                        ),
                        if (widget.isVideo)
                          _GroupControl(
                            icon: _cameraOn
                                ? Icons.videocam_rounded
                                : Icons.videocam_off_rounded,
                            active: !_cameraOn,
                            onTap: () {
                              setState(() => _cameraOn = !_cameraOn);
                              GroupCallService.instance.toggleCamera(_cameraOn);
                            },
                          ),
                        _GroupControl(
                          icon: Icons.call_end_rounded,
                          color: AppTheme.negative,
                          onTap: _leave,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.name,
    required this.renderer,
    required this.showVideo,
    required this.mirror,
  });

  final String name;
  final RTCVideoRenderer? renderer;
  final bool showVideo;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: const Color(0xFF1B2030),
            alignment: Alignment.center,
            child: CircleAvatar(
              radius: 34,
              backgroundColor: Colors.white12,
              child: Text(
                initial,
                style: const TextStyle(fontSize: 27, color: Colors.white),
              ),
            ),
          ),
          if (showVideo && renderer != null)
            RTCVideoView(
              renderer!,
              mirror: mirror,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupControl extends StatelessWidget {
  const _GroupControl({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.color,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) => Material(
    color: color ?? (active ? Colors.white : Colors.white12),
    shape: const CircleBorder(),
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Icon(
          icon,
          color: active && color == null ? Colors.black : Colors.white,
        ),
      ),
    ),
  );
}

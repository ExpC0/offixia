import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/call.dart';
import '../models/employee.dart';
import '../models/organization.dart';
import '../screens/call_screen.dart';
import 'call_service.dart';

/// Starting a call from anywhere in the app.
///
/// The permission request, the signalling and the navigation belong together:
/// every entry point needs all three in the same order, and scattering them
/// across screens is how one of them ends up missing.
class Calls {
  Calls._();

  /// Microphone always, camera only for video. Asked immediately before the
  /// call rather than at startup, so the prompt arrives when the reason for it
  /// is obvious.
  static Future<bool> ensurePermissions({required bool video}) async {
    final wanted = <Permission>[
      Permission.microphone,
      if (video) Permission.camera,
    ];

    final results = await wanted.request();
    return results.values.every((status) => status.isGranted);
  }

  /// Places a call and opens the call screen.
  static Future<void> start({
    required BuildContext context,
    required Organization organization,
    required Employee me,
    required Employee other,
    required CallKind kind,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final video = kind == CallKind.video;

    final granted = await ensurePermissions(video: video);
    if (!granted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            video
                ? 'Camera and microphone access are needed for a video call.'
                : 'Microphone access is needed to make a call.',
          ),
        ),
      );
      return;
    }

    try {
      final callId = await CallService.instance.place(
        orgId: organization.id,
        me: me,
        other: other,
        kind: kind,
      );

      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreenRoute(
            organization: organization,
            me: me,
            callId: callId,
            otherName: other.name,
            isVideo: video,
          ),
        ),
      );
    } catch (error) {
      // The peer connection may be half-open if this failed partway, and
      // leaving it would hold the microphone.
      await CallService.instance.hangUp();
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }
}

/// Thin alias so screens do not each import the call screen directly.
class CallScreenRoute extends StatelessWidget {
  const CallScreenRoute({
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
  final bool outgoing;

  @override
  Widget build(BuildContext context) => CallScreen(
    organization: organization,
    me: me,
    callId: callId,
    otherName: otherName,
    isVideo: isVideo,
    outgoing: outgoing,
  );
}

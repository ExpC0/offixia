import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Real Android notifications for messages that arrive while the app is alive.
///
/// `SystemSound.play` was the first attempt and is close to useless here: on
/// most Android builds it is silent unless the app already has focus, and it
/// cannot vibrate. Posting to a notification channel is what gets the device's
/// own tone and vibration, chosen by the user in system settings rather than
/// hard-coded here.
///
/// This still requires the app process to be running. Delivery to a closed app
/// needs FCM and a server to hold the credentials.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _channelId = 'com.rian.offixia.messages';
  static const _channelName = 'Messages';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  /// Set when the channel exists and permission has been granted, so callers
  /// can fall back rather than silently doing nothing.
  bool get ready => _ready;

  Future<void> initialize() async {
    if (_ready) return;

    const settings = InitializationSettings(
      // Bare resource name, not '@drawable/...': the plugin looks this up by
      // identifier and the '@' form fails with invalid_icon.
      //
      // A white silhouette, because Android treats the small icon as an alpha
      // mask -- a full-colour launcher icon can leave the post silently
      // dropped, the same trap that hid StreamTune's media notification.
      android: AndroidInitializationSettings('ic_stat_offixia'),
    );

    try {
      await _plugin.initialize(settings: settings);

      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      // Created up front. Android takes the sound and vibration settings from
      // the channel at creation time and ignores later changes, so this must
      // be right the first time.
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'New chat messages',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );

      await android?.requestNotificationsPermission();

      // Ready even if permission was refused: the channel exists, and Android
      // simply drops the posts. Treating refusal as "not ready" would also
      // suppress the in-app banner, which needs no permission at all.
      _ready = true;
    } catch (e) {
      debugPrint('offixia: notifications unavailable: $e');
      _ready = false;
    }
  }

  Future<void> showMessage({
    required String id,
    required String title,
    required String body,
  }) async {
    if (!_ready) return;

    try {
      await _plugin.show(
        // Stable per conversation, so a second message replaces the first
        // rather than stacking a separate notification for every line.
        id: id.hashCode & 0x7fffffff,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'New chat messages',
            importance: Importance.high,
            priority: Priority.high,
            ticker: 'New message',
            // Let Android suppress sender/message text on a secure lock screen
            // while still showing that Offixia has a notification.
            visibility: NotificationVisibility.private,
          ),
        ),
      );
    } catch (e) {
      debugPrint('offixia: could not post notification: $e');
    }
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat.dart';
import 'chat_service.dart';
import 'notification_service.dart';

/// In-app alerts and unread tracking for chat.
///
/// Deliberately not push. Delivering a notification while the app is closed
/// needs a server to hold the FCM credentials, and that means Cloud Functions
/// and a billing plan. This covers the case that works for free: you are in
/// the app, a colleague writes, and you find out without having to go looking.
///
/// Read state is kept on the device rather than in Firestore. It is per-person
/// and per-install by nature, nobody else ever needs to query it, and writing
/// it to the database would mean a write on every conversation you open.
class ChatAlertsService {
  ChatAlertsService._();

  static final ChatAlertsService instance = ChatAlertsService._();

  /// Namespaced by uid.
  ///
  /// A shared key meant that signing out and back in as a colleague inherited
  /// the previous person's read markers, so every conversation they had never
  /// opened already looked read. On a shared or test device that makes unread
  /// look simply broken.
  static String _prefsKeyFor(String uid) => 'chatLastSeen_$uid';

  /// Conversations holding a message newer than the last time this device
  /// opened them.
  final ValueNotifier<Set<String>> unread = ValueNotifier<Set<String>>({});

  StreamSubscription<List<ChatGroup>>? _sub;
  Map<String, DateTime> _lastSeen = {};

  /// The newest message time seen per conversation, straight off the server.
  ///
  /// Read markers are stored from this rather than from `DateTime.now()`:
  /// message times are server-stamped, the device clock is not, and a phone
  /// running even slightly fast would write a "seen" marker in the future and
  /// then treat genuinely newer messages as already read.
  final Map<String, DateTime> _latest = {};
  String? _openChatId;
  String? _uid;

  /// True until the first snapshot has been absorbed.
  ///
  /// Firestore replays everything already in the conversation list when the
  /// listener attaches. Without this, opening the app would fire an alert for
  /// every conversation that had ever received a message.
  bool _priming = true;

  Future<void> start({required String orgId, required String uid}) async {
    if (_uid == uid && _sub != null) return;

    await stop();
    _uid = uid;
    _priming = true;
    await _loadSeen(uid);

    _sub = ChatService.instance
        .myChats(orgId, uid)
        .listen(_onChats, onError: (Object e) {
          debugPrint('offixia/alerts: stream error: $e');
        });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _uid = null;
    _openChatId = null;
    _priming = true;
    // Cleared so a different account signing in on this device starts from
    // its own state rather than inheriting whatever is still in memory.
    _lastSeen = {};
    _latest.clear();
    unread.value = {};
  }

  /// Called by the thread screen so a conversation you are reading never
  /// alerts you about itself.
  ///
  /// Marks read on the way in *and* on the way out: anything that arrived
  /// while you were looking at the thread has been seen, and would otherwise
  /// come back as unread the moment you left.
  void setOpenChat(String? chatId) {
    final leaving = _openChatId;
    _openChatId = chatId;

    if (chatId != null) {
      unawaited(markRead(chatId));
    } else if (leaving != null) {
      unawaited(markRead(leaving));
    }
  }

  Future<void> markRead(String chatId) async {
    // Mark up to the newest message actually seen, in server time.
    _lastSeen[chatId] = _latest[chatId] ?? DateTime.now();
    unread.value = {...unread.value}..remove(chatId);
    await _saveSeen();
  }

  void _onChats(List<ChatGroup> chats) {
    final uid = _uid;
    if (uid == null) return;

    final nextUnread = <String>{};
    ChatGroup? alert;

    for (final chat in chats) {
      final at = chat.lastMessageAt;
      if (at == null || chat.lastMessage.isEmpty) continue;
      _latest[chat.id] = at;

      // Your own message is never unread and never alerts.
      if (chat.lastSenderUid == uid) continue;

      final seen = _lastSeen[chat.id];
      final isNew = seen == null || at.isAfter(seen);

      if (!isNew) continue;

      if (chat.id == _openChatId) {
        // On screen right now: keep the read marker moving forward instead of
        // letting it pile up as unread the moment they look away.
        _lastSeen[chat.id] = at;
        continue;
      }

      nextUnread.add(chat.id);

      // Alert for the most recent one only. A burst of messages should be one
      // interruption, not one per conversation.
      if (!_priming && (alert == null || at.isAfter(alert.lastMessageAt!))) {
        alert = chat;
      }
    }

    unread.value = nextUnread;

    if (alert != null) {
      // A real notification, so the tone and vibration are whatever the user
      // chose in system settings rather than something hard-coded.
      unawaited(
        NotificationService.instance.showMessage(
          id: alert.id,
          title: alert.isDirect ? alert.lastSenderName : alert.name,
          body: alert.isDirect
              ? alert.lastMessage
              : '${alert.lastSenderName}: ${alert.lastMessage}',
        ),
      );
    }

    if (_priming) {
      _priming = false;
      unawaited(_saveSeen());
    }
  }

  Future<void> _loadSeen(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyFor(uid));
    if (raw == null) {
      _lastSeen = {};
      return;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _lastSeen = decoded.map(
        (key, value) => MapEntry(
          key,
          DateTime.fromMillisecondsSinceEpoch(value as int),
        ),
      );
    } catch (_) {
      // Corrupt or from an older shape: start over rather than crash on open.
      _lastSeen = {};
    }
  }

  Future<void> _saveSeen() async {
    final uid = _uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKeyFor(uid),
      jsonEncode(
        _lastSeen.map(
          (key, value) => MapEntry(key, value.millisecondsSinceEpoch),
        ),
      ),
    );
  }
}

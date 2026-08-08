import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Plays phone-native incoming and outgoing call tones on Android.
class CallToneService {
  CallToneService._();

  static const _channel = MethodChannel('com.rian.offixia/call_tone');

  static Future<void> incoming() => _invoke('incoming');
  static Future<void> outgoing() => _invoke('outgoing');
  static Future<void> stop() => _invoke('stop');

  static Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Keeps desktop/tests usable; call tones are an Android concern.
    } catch (error) {
      debugPrint('offixia: call tone $method failed: $error');
    }
  }
}

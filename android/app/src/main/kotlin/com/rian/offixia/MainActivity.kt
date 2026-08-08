package com.rian.offixia

import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.rian.offixia/call_tone"
    private var ringtone: Ringtone? = null
    private var ringback: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "incoming" -> {
                        stopTones()
                        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                        ringtone = RingtoneManager.getRingtone(applicationContext, uri)?.also {
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                                it.isLooping = true
                            }
                            it.play()
                        }
                        result.success(null)
                    }
                    "outgoing" -> {
                        stopTones()
                        ringback = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 70).also {
                            it.startTone(ToneGenerator.TONE_SUP_RINGTONE)
                        }
                        result.success(null)
                    }
                    "stop" -> {
                        stopTones()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun stopTones() {
        ringtone?.stop()
        ringtone = null
        ringback?.stopTone()
        ringback?.release()
        ringback = null
    }

    override fun onDestroy() {
        stopTones()
        super.onDestroy()
    }
}

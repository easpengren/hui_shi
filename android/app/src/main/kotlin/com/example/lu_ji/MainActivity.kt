package com.example.lu_ji

import android.content.Intent
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Receives text shared from another app and hands it to Dart.
 *
 * Confucius extracts the readable article from a shared link — a web page is
 * mostly navigation, and reading that aloud is worse than not reading — and
 * shares the prose here. LuJi supplies the part Confucius has no business
 * duplicating: the voices and the reader.
 *
 * The pending/consume shape mirrors the one on the Confucius side. It exists
 * because a share can arrive before Dart is listening (cold start) or while it
 * already is (`onNewIntent`), and only the second can be pushed.
 */
// AudioServiceActivity (not FlutterActivity, which it extends) so
// audio_service's media session and foreground service bind correctly —
// without it playback stops when the screen goes off. The share-intent
// handling below is unaffected.
class MainActivity : AudioServiceActivity() {
    private var pendingSharedText: String? = null
    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingSharedText = sharedTextOf(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val shared = sharedTextOf(intent) ?: return
        pendingSharedText = shared
        // Already running: nothing will ask again on its own, so say so.
        channel?.invokeMethod("sharedTextArrived", null)
    }

    private fun sharedTextOf(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND) return null
        if (intent.type?.startsWith("text/") != true) return null
        return intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()?.takeIf { it.isNotEmpty() }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lu_ji/share",
        ).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    // Read-and-clear, so a resume cannot re-open the same share.
                    "consumeSharedText" -> {
                        val text = pendingSharedText
                        pendingSharedText = null
                        result.success(text)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
}

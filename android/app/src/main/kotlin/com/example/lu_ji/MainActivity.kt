package com.example.lu_ji

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.util.Log
import android.os.Build
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
    private var notificationPermissionResult: MethodChannel.Result? = null

    private companion object {
        const val NOTIFICATION_PERMISSION_REQUEST = 8801
    }

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

    /**
     * Ask for POST_NOTIFICATIONS, which read-aloud needs to survive the screen
     * going off.
     *
     * This looks like a cosmetic permission and is not. A `mediaPlayback`
     * foreground service is defined by its visible notification; ungranted, the
     * notification is suppressed, the service does not hold the process, and
     * Android suspends the app on sleep — playback stops and the reading
     * position dies with the process. Framework APIs rather than androidx so
     * this pulls in nothing: the permission only exists on API 33+, which is
     * exactly where these calls are available.
     */
    private fun ensureNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true) // Pre-13: granted at install time.
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        // Only one request can be in flight; answer any earlier one rather than
        // dropping its Result on the floor, which leaves Dart awaiting forever.
        notificationPermissionResult?.success(false)
        notificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        // super first: the Flutter embedding forwards results to plugins, and
        // swallowing them here would break any plugin permission flow.
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return
        val pending = notificationPermissionResult ?: return
        notificationPermissionResult = null
        pending.success(
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED,
        )
    }

    /**
     * The shared text, however the sender managed to hand it over.
     *
     * `EXTRA_TEXT` is the ordinary path and stays first. It is also the one that
     * breaks: an intent extra travels through a Binder transaction, and the whole
     * transaction budget is about 1 MB shared with everything else in flight.
     * Four Books handing over the Platform Sutra — 225,034 characters, a 668 KB
     * parcel — produced
     *
     *     android.os.TransactionTooLargeException: data parcel size 683620 bytes
     *     Second failure launching com.example.lu_ji/.MainActivity, giving up
     *
     * and the process died before Flutter ever started. From the outside that is
     * a black screen and a bounce back to the sender, which is exactly what it
     * looked like. Nothing here was at fault; this activity never ran.
     *
     * So a URI is accepted too — `EXTRA_STREAM`, or the intent's own data — and
     * read through the ContentResolver. A `content://` URI is a handle, a few
     * dozen bytes, and the size of the text stops mattering. The sender grants
     * read access with FLAG_GRANT_READ_URI_PERMISSION; without it this throws
     * SecurityException, which is caught and reported as "nothing to read"
     * rather than a crash.
     */
    private fun sharedTextOf(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND && intent?.action != Intent.ACTION_VIEW) {
            return null
        }
        intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()?.takeIf { it.isNotEmpty() }
            ?.let { return it }

        @Suppress("DEPRECATION")
        val uri: Uri? = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: intent.data
        if (uri == null) return null
        return try {
            contentResolver.openInputStream(uri)?.use { stream ->
                stream.readBytes().toString(Charsets.UTF_8).trim().takeIf { it.isNotEmpty() }
            }
        } catch (error: Exception) {
            // Revoked grant, deleted file, or a sender that forgot the flag. A
            // share that cannot be read is nothing to read, not a crash.
            Log.w("LuJi", "could not read shared text from $uri", error)
            null
        }
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
                    "ensureNotificationPermission" ->
                        ensureNotificationPermission(result)
                    else -> result.notImplemented()
                }
            }
        }
    }
}

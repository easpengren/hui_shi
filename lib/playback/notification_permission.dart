/// The permission read-aloud needs in order to survive the screen going off.
///
/// ## Why a notification permission controls audio
///
/// It reads like chrome and is not. `audio_service` keeps playback alive with a
/// `mediaPlayback` **foreground service**, and on Android a foreground service
/// *is* its visible notification — that notification is the entire user-facing
/// justification for the process being exempt from suspension. Since Android 13
/// posting it requires `POST_NOTIFICATIONS`, a runtime permission. Ungranted:
///
///   * no media notification and no lock-screen controls;
///   * the service does not hold the process as foreground;
///   * Android suspends the app when the screen goes off, so read-aloud stops
///     mid-sentence;
///   * and the reading position is lost with it, because the process dies
///     before the debounced save finishes its several async hops.
///
/// One missing line in the manifest produced all four symptoms, and only the
/// first one looked like a notification problem.
///
/// `audio_service` declares no permissions of its own, so both halves are this
/// app's job: the `<uses-permission>` entry in `AndroidManifest.xml` **and** the
/// runtime request below. Declaring it alone changes nothing on a modern phone.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('lu_ji/share');

/// Ask for notification permission, returning whether playback can now hold the
/// screen-off case.
///
/// Returns true on anything that is not Android 13+ (where the permission is
/// granted at install) and on any platform that does not implement the call —
/// a missing channel must not read as "denied" and scare the caller into
/// disabling playback.
Future<bool> requestNotificationPermission() async {
  if (defaultTargetPlatform != TargetPlatform.android) return true;
  try {
    final granted =
        await _channel.invokeMethod<bool>('ensureNotificationPermission');
    return granted ?? true;
  } on MissingPluginException {
    return true;
  } on PlatformException {
    return true;
  }
}

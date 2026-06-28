import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// A newer build advertised by the update manifest.
class UpdateInfo {
  UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.notes,
  });

  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String notes;
}

/// Self-update for the sideloaded app: poll a JSON manifest published next to
/// the APK by CI, compare its version_code to the running build, and (on
/// request) download + install the new APK via the system installer.
///
/// Works because every CI build uses a monotonically increasing build-number
/// (github.run_number) and the same signing key, so Android treats the new APK
/// as an in-place upgrade.
class AppUpdater {
  AppUpdater({this.manifestUrl = _defaultManifestUrl});

  static const _defaultManifestUrl =
      'https://confucius.monolithstudio.art/downloads/lu_ji-latest.json';

  final String manifestUrl;

  /// The running build number (== the CI run_number it was built from).
  Future<int> currentVersionCode() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// Returns [UpdateInfo] when the manifest advertises a newer build, else null.
  Future<UpdateInfo?> checkForUpdate() async {
    final res = await http
        .get(Uri.parse(manifestUrl))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final remoteCode = (data['version_code'] as num?)?.toInt() ?? 0;
    final apkUrl = data['apk_url']?.toString() ?? '';
    if (remoteCode <= await currentVersionCode() || apkUrl.isEmpty) return null;
    return UpdateInfo(
      versionCode: remoteCode,
      versionName: data['version_name']?.toString() ?? '$remoteCode',
      apkUrl: apkUrl,
      notes: data['notes']?.toString() ?? '',
    );
  }

  /// Downloads the APK and launches the system installer. Emits OtaEvents for
  /// progress (DOWNLOADING with a percent value) and terminal status.
  Stream<OtaEvent> install(String apkUrl) {
    return OtaUpdate().execute(
      apkUrl,
      destinationFilename: 'lu_ji-update.apk',
    );
  }
}

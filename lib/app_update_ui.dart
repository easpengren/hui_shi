import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

import 'services/app_updater.dart';

/// Checks the update manifest and, if a newer build exists, offers to install
/// it. With [manual] true (the Settings button) it also reports when already up
/// to date or when the check fails; on launch it stays silent in those cases.
Future<void> checkAndOfferUpdate(
  BuildContext context, {
  AppUpdater? updater,
  bool manual = false,
}) async {
  final u = updater ?? AppUpdater();
  UpdateInfo? info;
  try {
    info = await u.checkForUpdate();
  } catch (_) {
    if (manual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not check for updates.')),
      );
    }
    return;
  }
  if (info == null) {
    if (manual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're on the latest version.")),
      );
    }
    return;
  }
  if (!context.mounted) return;
  final update = info;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Update available — ${update.versionName}'),
      content: Text(
        update.notes.isNotEmpty
            ? 'Build ${update.notes}.\n\nDownload and install now?'
            : 'Download and install now?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Update'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  await _installWithProgress(context, u, update);
}

Future<void> _installWithProgress(
  BuildContext context,
  AppUpdater updater,
  UpdateInfo info,
) async {
  final status = ValueNotifier<String>('Starting…');
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Downloading update'),
      content: ValueListenableBuilder<String>(
        valueListenable: status,
        builder: (_, v, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(v)),
          ],
        ),
      ),
    ),
  );
  try {
    await for (final ev in updater.install(info.apkUrl)) {
      switch (ev.status) {
        case OtaStatus.DOWNLOADING:
          status.value = 'Downloading… ${ev.value ?? ''}%';
        case OtaStatus.INSTALLING:
          status.value = 'Opening installer…';
        case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
          status.value =
              'Allow "install unknown apps" for Lu Ji, then try again.';
        default:
          status.value = 'Update failed (${ev.status.name}).';
      }
    }
  } catch (_) {
    // Stream errors surface as the last status; nothing more to do.
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
}

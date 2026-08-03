import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lu_ji/tts/piper_tts_client.dart';

/// What counts as "this voice is installed" (confucius#65).
///
/// The download reported success on the strength of nothing having thrown, and
/// the app set `piperModelDownloaded = true` on the same non-evidence. A
/// partial or unexpected archive therefore looked installed and only failed
/// later, at the moment the owner pressed play — which is what "Piper voices
/// broken" looks like from outside.
///
/// The fix makes both the client and the state ask this predicate instead of
/// assuming, so the predicate is what has to be right.
void main() {
  late Directory modelsDir;

  setUp(() {
    modelsDir = Directory.systemTemp.createTempSync('piper-models-');
  });

  tearDown(() {
    if (modelsDir.existsSync()) modelsDir.deleteSync(recursive: true);
  });

  /// Lay out a voice the way the sherpa-onnx tarball does once its top-level
  /// directory has been stripped: `<voice>.onnx`, `tokens.txt`,
  /// `espeak-ng-data/`. Verified against the real
  /// `vits-piper-en_US-lessac-medium.tar.bz2`.
  void layOutVoice(
    String voice, {
    int onnxBytes = 16,
    int tokensBytes = 8,
    bool espeak = true,
  }) {
    final dir = Directory('${modelsDir.path}/$voice')..createSync(recursive: true);
    File('${dir.path}/$voice.onnx').writeAsBytesSync(List.filled(onnxBytes, 0));
    File('${dir.path}/tokens.txt').writeAsBytesSync(List.filled(tokensBytes, 0));
    if (espeak) {
      Directory('${dir.path}/espeak-ng-data').createSync(recursive: true);
    }
  }

  PiperTtsClient client() => PiperTtsClient.forTesting(modelsDir: modelsDir);

  test('a complete extraction counts as installed', () {
    layOutVoice('en_US-lessac-medium');
    expect(client().isModelDownloaded('en_US-lessac-medium'), isTrue);
  });

  test('a voice that was never downloaded is not installed', () {
    expect(client().isModelDownloaded('en_GB-alan-medium'), isFalse);
  });

  test('a zero-byte model does not count as installed', () {
    // The shape a truncated or interrupted extraction leaves behind: the file
    // exists, so an `existsSync()` check alone would call this a success.
    layOutVoice('en_US-amy-medium', onnxBytes: 0);
    expect(client().isModelDownloaded('en_US-amy-medium'), isFalse);
  });

  test('a zero-byte tokens file does not count as installed', () {
    layOutVoice('en_US-amy-medium', tokensBytes: 0);
    expect(client().isModelDownloaded('en_US-amy-medium'), isFalse);
  });

  test('missing espeak-ng-data does not count as installed', () {
    // Present in every real tarball and required by the engine config; without
    // it the voice loads and then fails to speak.
    layOutVoice('en_US-ryan-high', espeak: false);
    expect(client().isModelDownloaded('en_US-ryan-high'), isFalse);
  });

  test('voices are judged independently of one another', () {
    layOutVoice('en_US-lessac-medium');
    final c = client();
    expect(c.isModelDownloaded('en_US-lessac-medium'), isTrue);
    expect(c.isModelDownloaded('en_US-lessac-high'), isFalse);
  });
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lu_ji/tts/silence_trim.dart';
import 'package:lu_ji/tts/wav_utils.dart';

/// The unnatural pause was the padding silence every TTS clip carries, stacking
/// at each chunk boundary. These guard the trim that removes it — remove the
/// trim and a padded clip stops getting shorter, and the pause is back.
void main() {
  const sr = 16000;

  Float32List padded({
    double lead = 0.5,
    double tone = 0.2,
    double trail = 0.5,
    double amp = 0.5,
  }) {
    final total = ((lead + tone + trail) * sr).round();
    final s = Float32List(total);
    final start = (lead * sr).round();
    final end = ((lead + tone) * sr).round();
    for (var i = start; i < end; i++) {
      s[i] = amp;
    }
    return s;
  }

  group('trimSilenceSamples', () {
    test('removes the padding but keeps the speech (and a margin)', () {
      final s = padded();
      final out = trimSilenceSamples(s, sr, leadMarginMs: 20, trailMarginMs: 90);
      // Much shorter than the 1.2s original...
      expect(out.length, lessThan(s.length));
      // ...but at least the 0.2s tone plus both margins survives.
      final minKept = (sr * (0.2 + 0.02 + 0.09)).round();
      expect(out.length, greaterThanOrEqualTo((sr * 0.2).round()));
      expect(out.length, lessThanOrEqualTo(minKept + 2));
      // The speech itself is intact.
      final peak = out.fold<double>(0, (m, v) => v.abs() > m ? v.abs() : m);
      expect(peak, closeTo(0.5, 1e-6));
    });

    test('an all-silence clip is left exactly as-is (a deliberate pause)', () {
      final s = Float32List(1000);
      expect(identical(trimSilenceSamples(s, sr), s), isTrue);
    });

    test('a clip with nothing to trim is returned unchanged', () {
      final s = Float32List.fromList(List.filled(1000, 0.5));
      expect(identical(trimSilenceSamples(s, sr), s), isTrue);
    });
  });

  group('trimSilenceWav', () {
    test('trims a 16-bit PCM WAV and keeps it a valid WAV', () {
      final wav = float32ToWav(padded(), sr);
      final out = trimSilenceWav(wav);
      expect(out, isNotNull);
      expect(out!.length, lessThan(wav.length));
      expect(String.fromCharCodes(out.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(out.sublist(8, 12)), 'WAVE');
      // Sample rate preserved in the rewritten header.
      final bd = ByteData.sublistView(out);
      expect(bd.getUint32(24, Endian.little), sr);
    });

    test('non-WAV bytes return null (caller keeps the original)', () {
      expect(trimSilenceWav(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });
}

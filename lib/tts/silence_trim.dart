import 'dart:typed_data';

/// Trim the padding silence a TTS engine bakes into each synthesized clip.
///
/// Read-aloud plays one clip per chunk (a sentence, a list item, a paragraph),
/// back to back. Every engine — Piper and the system TTS both — pads the start
/// and (especially) the end of an utterance with silence. Played in sequence
/// that padding stacks into an audible, unnatural pause at *every* boundary, and
/// it is worst where the text is densely broken into short chunks. Trimming it
/// leaves a short, consistent gap instead: the reading flows, and a sentence's
/// own falling cadence (which lives in the speech, before the padding) is kept.
///
/// Conservative by construction: it only ever REMOVES leading/trailing samples
/// that are below [threshold], keeps [leadMarginMs]/[trailMarginMs] of silence
/// so nothing is clipped and clips don't butt together, and never touches a clip
/// that is silent end to end (a deliberate pause chunk) — so it cannot make
/// audio sound worse, only less padded.

const double _defaultThreshold = 0.01; // ~-40 dBFS
const int _defaultLeadMarginMs = 20;
const int _defaultTrailMarginMs = 90;

/// The [start, end] sample bounds to keep, or null when the whole clip is
/// silence (leave it alone) or there is nothing to trim.
List<int>? _keepBounds(
  double Function(int) amplitudeAt,
  int length,
  int sampleRate, {
  required double threshold,
  required int leadMarginMs,
  required int trailMarginMs,
}) {
  if (length == 0) return null;
  var start = 0;
  while (start < length && amplitudeAt(start) < threshold) {
    start++;
  }
  if (start == length) return null; // all silence — a pause; do not trim
  var end = length - 1;
  while (end > start && amplitudeAt(end) < threshold) {
    end--;
  }
  final lead = (sampleRate * leadMarginMs / 1000).round();
  final trail = (sampleRate * trailMarginMs / 1000).round();
  final from = (start - lead) < 0 ? 0 : start - lead;
  final to = (end + trail) >= length ? length - 1 : end + trail;
  if (from == 0 && to == length - 1) return null; // nothing to trim
  return [from, to];
}

/// Trim padding silence off a mono [Float32List] (the Piper path). Returns the
/// input unchanged when there is nothing to trim or the clip is all silence.
Float32List trimSilenceSamples(
  Float32List samples,
  int sampleRate, {
  double threshold = _defaultThreshold,
  int leadMarginMs = _defaultLeadMarginMs,
  int trailMarginMs = _defaultTrailMarginMs,
}) {
  final bounds = _keepBounds(
    (i) => samples[i].abs(),
    samples.length,
    sampleRate,
    threshold: threshold,
    leadMarginMs: leadMarginMs,
    trailMarginMs: trailMarginMs,
  );
  if (bounds == null) return samples;
  return Float32List.sublistView(samples, bounds[0], bounds[1] + 1);
}

/// Trim padding silence from a 16-bit PCM WAV (the system-TTS path, and what our
/// own encoder produces). Returns null when the bytes are not a 16-bit PCM WAV
/// this understands or there is nothing to trim, so the caller keeps the
/// original file and playback is never put at risk.
Uint8List? trimSilenceWav(
  Uint8List wav, {
  double threshold = _defaultThreshold,
  int leadMarginMs = _defaultLeadMarginMs,
  int trailMarginMs = _defaultTrailMarginMs,
}) {
  try {
    if (wav.length < 44) return null;
    final bd = ByteData.sublistView(wav);
    if (String.fromCharCodes(wav.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(wav.sublist(8, 12)) != 'WAVE') {
      return null;
    }
    // Walk the chunks — some engines insert 'LIST'/'fact' before 'data'.
    int channels = 1;
    int sampleRate = 22050;
    int bits = 16;
    int? dataStart;
    int? dataLen;
    var p = 12;
    while (p + 8 <= wav.length) {
      final id = String.fromCharCodes(wav.sublist(p, p + 4));
      final size = bd.getUint32(p + 4, Endian.little);
      final body = p + 8;
      if (id == 'fmt ' && body + 16 <= wav.length) {
        channels = bd.getUint16(body + 2, Endian.little);
        sampleRate = bd.getUint32(body + 4, Endian.little);
        bits = bd.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        dataStart = body;
        dataLen = size;
        break;
      }
      p = body + size + (size.isOdd ? 1 : 0); // chunks are word-aligned
    }
    if (dataStart == null || dataLen == null) return null;
    if (bits != 16 || channels < 1) return null;
    final end = dataStart + dataLen;
    if (end > wav.length) return null;

    final bytesPerFrame = 2 * channels;
    final frames = dataLen ~/ bytesPerFrame;
    if (frames == 0) return null;

    // Amplitude per frame = the loudest channel, normalised to 0..1.
    double amp(int frame) {
      final base = dataStart! + frame * bytesPerFrame;
      var peak = 0;
      for (var c = 0; c < channels; c++) {
        final s = bd.getInt16(base + c * 2, Endian.little).abs();
        if (s > peak) peak = s;
      }
      return peak / 32768.0;
    }

    final bounds = _keepBounds(
      amp,
      frames,
      sampleRate,
      threshold: threshold,
      leadMarginMs: leadMarginMs,
      trailMarginMs: trailMarginMs,
    );
    if (bounds == null) return null;

    final firstByte = dataStart + bounds[0] * bytesPerFrame;
    final lastByte = dataStart + (bounds[1] + 1) * bytesPerFrame; // exclusive
    final pcm = wav.sublist(firstByte, lastByte);
    return _wrapPcm16(pcm, channels: channels, sampleRate: sampleRate);
  } catch (_) {
    return null;
  }
}

/// Wrap raw 16-bit little-endian PCM in a minimal canonical WAV header.
Uint8List _wrapPcm16(
  Uint8List pcm, {
  required int channels,
  required int sampleRate,
}) {
  const bytesPerSample = 2;
  final byteRate = sampleRate * channels * bytesPerSample;
  final blockAlign = channels * bytesPerSample;
  final out = ByteData(44 + pcm.length);
  var o = 0;
  void s(String v) {
    for (var i = 0; i < v.length; i++) {
      out.setUint8(o + i, v.codeUnitAt(i));
    }
    o += v.length;
  }

  void i32(int v) {
    out.setUint32(o, v, Endian.little);
    o += 4;
  }

  void i16(int v) {
    out.setUint16(o, v, Endian.little);
    o += 2;
  }

  s('RIFF');
  i32(36 + pcm.length);
  s('WAVE');
  s('fmt ');
  i32(16);
  i16(1); // PCM
  i16(channels);
  i32(sampleRate);
  i32(byteRate);
  i16(blockAlign);
  i16(16);
  s('data');
  i32(pcm.length);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(44, 44 + pcm.length, pcm);
  return bytes;
}

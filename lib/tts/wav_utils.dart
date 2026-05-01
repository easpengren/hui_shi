import 'dart:typed_data';

/// Encode a [Float32List] of audio samples into a minimal 16-bit mono WAV.
Uint8List float32ToWav(Float32List samples, int sampleRate) {
  const int bytesPerSample = 2;
  final int dataSize = samples.length * bytesPerSample;
  final buffer = ByteData(44 + dataSize);
  var offset = 0;

  void writeStr(String s) {
    for (var i = 0; i < s.length; i++) {
      buffer.setUint8(offset + i, s.codeUnitAt(i));
    }
    offset += s.length;
  }

  void writeI32(int v) {
    buffer.setInt32(offset, v, Endian.little);
    offset += 4;
  }

  void writeI16(int v) {
    buffer.setInt16(offset, v, Endian.little);
    offset += 2;
  }

  writeStr('RIFF');
  writeI32(36 + dataSize);
  writeStr('WAVE');
  writeStr('fmt ');
  writeI32(16); // PCM chunk size
  writeI16(1); // PCM format
  writeI16(1); // mono
  writeI32(sampleRate);
  writeI32(sampleRate * bytesPerSample); // byte rate
  writeI16(bytesPerSample); // block align
  writeI16(16); // bits per sample
  writeStr('data');
  writeI32(dataSize);

  for (final sample in samples) {
    final pcm = (sample * 32767.0).clamp(-32768.0, 32767.0).round();
    buffer.setInt16(offset, pcm, Endian.little);
    offset += 2;
  }

  return buffer.buffer.asUint8List();
}

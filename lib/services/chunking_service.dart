const int kMaxChunkLength = 280;

/// Split [text] into very small TTS-friendly chunks.
/// Default behavior is sentence-first chunking so playback controls feel
/// responsive and pause/resume can continue near sentence boundaries.
List<String> chunkText(String text, {int maxLen = kMaxChunkLength}) {
  final normalized = text
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();
  if (normalized.isEmpty) return const [];

  final chunks = <String>[];

  // Sentence boundaries for Latin and CJK punctuation.
  final sentenceParts = normalized.split(RegExp(r'(?<=[.!?;。！？；…])\s+|\n+'));

  for (final part in sentenceParts) {
    final sentence = part.trim();
    if (sentence.isEmpty) continue;

    if (sentence.length <= maxLen) {
      chunks.add(sentence);
      continue;
    }

    // If a single sentence is still too long, split by clause punctuation,
    // then hard-split as a last resort.
    final clauses = sentence.split(RegExp(r'(?<=[,，:：])\s*'));
    final buffer = StringBuffer();
    for (final clause in clauses) {
      final c = clause.trim();
      if (c.isEmpty) continue;

      if (buffer.length + c.length + 1 > maxLen && buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }

      if (c.length > maxLen) {
        var start = 0;
        while (start < c.length) {
          final end = (start + maxLen).clamp(0, c.length);
          chunks.add(c.substring(start, end).trim());
          start = end;
        }
        continue;
      }

      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(c);
    }

    if (buffer.isNotEmpty) {
      chunks.add(buffer.toString().trim());
    }
  }

  return chunks.where((c) => c.isNotEmpty).toList(growable: false);
}

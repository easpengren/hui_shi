const int kMaxChunkLength = 2000;

/// Split [text] into TTS-friendly chunks.
/// Splits on double-newlines (paragraphs) first; falls back to sentence
/// splitting for paragraphs that exceed [maxLen].
List<String> chunkText(String text, {int maxLen = kMaxChunkLength}) {
  final paragraphs = text.split(RegExp(r'\n\s*\n'));
  final chunks = <String>[];
  final buffer = StringBuffer();

  for (final paragraph in paragraphs) {
    final p = paragraph.trim();
    if (p.isEmpty) continue;

    if (buffer.length + p.length + 2 > maxLen) {
      if (buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }
      if (p.length > maxLen) {
        chunks.addAll(_splitBySentence(p, maxLen));
        continue;
      }
    }

    if (buffer.isNotEmpty) buffer.write('\n\n');
    buffer.write(p);
  }

  if (buffer.isNotEmpty) chunks.add(buffer.toString().trim());
  return chunks.where((c) => c.isNotEmpty).toList();
}

List<String> _splitBySentence(String text, int maxLen) {
  final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
  final chunks = <String>[];
  final buffer = StringBuffer();

  for (final sentence in sentences) {
    if (buffer.length + sentence.length + 1 > maxLen && buffer.isNotEmpty) {
      chunks.add(buffer.toString().trim());
      buffer.clear();
    }
    if (buffer.isNotEmpty) buffer.write(' ');
    buffer.write(sentence);
  }

  if (buffer.isNotEmpty) chunks.add(buffer.toString().trim());
  return chunks.where((c) => c.isNotEmpty).toList();
}

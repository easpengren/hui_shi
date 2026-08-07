import 'list_detector.dart';
import 'speech_normalizer.dart';

final _codeFenceRegex = RegExp(r'```[\s\S]*?```', multiLine: true);
final _markdownLinkRegex = RegExp(r'\[([^\]]+)\]\([^)]+\)');
final _headingRegex = RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true);
final _blockQuoteRegex = RegExp(r'^\s*>+\s?', multiLine: true);
final _xmlTagRegex = RegExp(r'<[^>]+>');
final _markdownFmtRegex = RegExp(r'[`*_~]');
final _whitespaceRegex = RegExp(r'\s+');

final _crlfRegex = RegExp(r'\r\n?');
final _horizontalRunRegex = RegExp('[ \\t\u00A0]+');

/// Strip Markdown and HTML markup from extracted document text.
///
/// **Paragraph breaks are preserved.** This function used to collapse all
/// whitespace with `\s+ -> ' '`, which silently disabled the paragraph branch
/// of [chunkText] — it splits on `\n\s*\n`, and after collapsing there were no
/// newlines left to find. Every document therefore arrived at the chunker as a
/// single paragraph and was cut by sentence heuristics alone, which is how
/// "George E. P. Box" ended up split across three chunks.
///
/// Three kinds of line break are distinguished:
///
///  * a blank line ends a paragraph;
///  * a line opening with a list marker starts its own block, so `1.` and `2.`
///    become separate chunks with their own highlight and pause — this is the
///    common shape of a list in a real document, one item per line;
///  * any other line break is a soft wrap from the source file's line width and
///    is flattened to a space.
String cleanText(String input) {
  final stripped = input
      .replaceAll(_codeFenceRegex, ' ')
      .replaceAllMapped(_markdownLinkRegex, (m) => m.group(1) ?? '')
      .replaceAll(_headingRegex, '')
      .replaceAll(_blockQuoteRegex, '')
      .replaceAll(_xmlTagRegex, ' ')
      .replaceAll(_markdownFmtRegex, ' ')
      .replaceAll(_crlfRegex, '\n')
      .replaceAll(_horizontalRunRegex, ' ');

  final paragraphs = <String>[];
  final current = StringBuffer();

  void flush() {
    final paragraph = current.toString().trim();
    if (paragraph.isNotEmpty) paragraphs.add(paragraph);
    current.clear();
  }

  for (final rawLine in stripped.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      flush();
      continue;
    }
    if (startsWithListMarker(line)) flush();
    if (current.isNotEmpty) current.write(' ');
    current.write(line);
  }
  flush();

  return paragraphs.join('\n\n');
}

/// Prepare a single chunk for a speech engine.
///
/// Unlike [cleanText] this *does* flatten everything to one line: it runs on a
/// single chunk on its way into the engine, where the chunk boundary already
/// supplies the pause and an embedded newline would only risk an artefact.
///
/// Output is never displayed — the reader renders the original chunk — so this
/// is free to rewrite text into what it should sound like. See
/// [normalizeForSpeech].
String sanitizeForTts(String input) {
  final stripped = input
      .replaceAll(_codeFenceRegex, ' ')
      .replaceAll(_xmlTagRegex, ' ')
      .replaceAll(_whitespaceRegex, ' ')
      .trim();
  return normalizeForSpeech(stripped);
}

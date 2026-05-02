final _codeFenceRegex = RegExp(r'```[\s\S]*?```', multiLine: true);
final _markdownLinkRegex = RegExp(r'\[([^\]]+)\]\([^)]+\)');
final _headingRegex = RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true);
final _blockQuoteRegex = RegExp(r'^\s*>+\s?', multiLine: true);
final _xmlTagRegex = RegExp(r'<[^>]+>');
final _markdownFmtRegex = RegExp(r'[`*_~]');
final _whitespaceRegex = RegExp(r'\s+');

/// Strip Markdown and HTML markup from extracted document text.
String cleanText(String input) {
  return input
      .replaceAll(_codeFenceRegex, ' ')
      .replaceAllMapped(_markdownLinkRegex, (m) => m.group(1) ?? '')
      .replaceAll(_headingRegex, '')
      .replaceAll(_blockQuoteRegex, '')
      .replaceAll(_xmlTagRegex, ' ')
      .replaceAll(_markdownFmtRegex, ' ')
      .replaceAll(_whitespaceRegex, ' ')
      .trim();
}

/// Strip markup that confuses TTS engines (code, tags, extra whitespace).
String sanitizeForTts(String input) {
  return input
      .replaceAll(_codeFenceRegex, ' ')
      .replaceAll(_xmlTagRegex, ' ')
  // Convert ellipses/dot-runs into pauses instead of spoken punctuation.
  .replaceAll(RegExp(r'\.{2,}|…+'), ' ')
  // Remove isolated single-dot tokens (" . ", leading/trailing ".").
  .replaceAll(RegExp(r'(^|\s)\.(?=\s|$)'), ' ')
      .replaceAll(_whitespaceRegex, ' ')
      .trim();
}

/// Navigating by the pages of the printed book.
///
/// A page number is **metadata, not a measurement**. It cannot be derived from
/// the text: two editions break pages differently, and a reflowable file has no
/// pages at all. So this never invents one. Pages exist only where the source
/// carried them, and a book without them reports that honestly rather than
/// offering a number that matches nothing on a shelf.
///
/// **How it survives this reader's pipeline.** Text here is one flat string
/// that is cleaned, chunked, filtered, and — for a large PDF — re-chunked from
/// scratch each time another batch of pages loads. An anchor stored as a chunk
/// index would be wrong after any of that. So the anchor is carried *in the
/// text itself*, as a `[Pg N]` marker on its own line, and converted to chunk
/// positions by [extractPageAnchors] after every chunking. Re-chunking simply
/// regenerates the map.
///
/// Where the numbers come from, by format:
///
///  * **PDF** — the folio printed on each page, read by
///    [printedPageNumberFromText] *before* `stripRepeatedHeadersFooters`
///    deletes it. This is the number in the book, not the index of the sheet:
///    the two differ by the whole of the front matter.
///  * **EPUB** — `epub:type="pagebreak"` anchors, rewritten to the same marker
///    by [markPageBreaksInHtml].
///  * **TXT** — `[Pg 45]` markers from a scanned original, which already are
///    that marker. Measured across five Project Gutenberg books and three URL
///    styles: none carried them. Supported, rarely fires.
library;

final _labelNoiseRegex = RegExp(r'^(page|pg|p)\.?\s*', caseSensitive: false);

/// Compare page labels forgivingly: "p. 12", "Page 12" and "12" are one page,
/// and roman numerals match regardless of case.
String normalizePageLabel(String label) =>
    label.trim().replaceFirst(_labelNoiseRegex, '').trim().toLowerCase();

/// The in-text anchor for a page. Emitted on its own line so it becomes its own
/// chunk and can be lifted out cleanly.
String pageMarkerFor(String label) => '[Pg $label]';

/// A marker occupying a whole chunk, or embedded in one.
final _markerRegex =
    RegExp(r'\[\s*(?:pg|page)\.?\s*([0-9ivxlcdm]{1,6})\s*\]', caseSensitive: false);

final _pureNumberLine = RegExp(r'^\d{1,4}$');
final _romanNumeralLine = RegExp(r'^[ivxlcdm]{2,7}$', caseSensitive: false);
final _pageLabelLine = RegExp(r'^(page|p\.?)\s*\d{1,4}$', caseSensitive: false);
final _pageLabelPrefix = RegExp(r'^(page|p)\.?\s*', caseSensitive: false);

bool _isPageNumberLine(String s) =>
    _pureNumberLine.hasMatch(s) ||
    _romanNumeralLine.hasMatch(s) ||
    _pageLabelLine.hasMatch(s);

/// The folio printed on a page of extracted PDF text, or null.
///
/// Must run before `stripRepeatedHeadersFooters`, which deletes exactly these
/// lines. Only the top and bottom [bandLines] are considered — a bare number in
/// the body of a page is data, not a folio — and the foot wins, since that is
/// where a folio usually sits.
String? printedPageNumberFromText(String pageText, {int bandLines = 2}) {
  final lines = [
    for (final l in pageText.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  if (lines.isEmpty) return null;

  final band = <String>[
    ...lines.take(bandLines),
    ...lines.skip(lines.length > bandLines ? lines.length - bandLines : 0),
  ];

  String? found;
  for (final line in band) {
    if (_isPageNumberLine(line)) {
      final value = line.replaceFirst(_pageLabelPrefix, '').trim();
      if (value.isNotEmpty) found = value;
    }
  }
  return found;
}

/// Carry a page sequence across pages that print no folio.
///
/// Chapter openings, plates and full-page illustrations routinely omit the
/// number while still counting. Anything detected on the page itself wins over
/// the assumption. Accepted failure: an unnumbered insert that does not count
/// shifts the rest until the next printed number corrects it.
List<String?> fillPageLabels(List<String?> detected) {
  final out = List<String?>.from(detected);
  for (var i = 1; i < out.length; i++) {
    if (out[i] != null) continue;
    final previous = int.tryParse(out[i - 1] ?? '');
    if (previous != null) out[i] = '${previous + 1}';
  }
  return out;
}

final _pagebreakTagRegex = RegExp(
  r'<[^>]*(?:epub:type\s*=\s*"[^"]*pagebreak[^"]*"'
  r'|role\s*=\s*"[^"]*doc-pagebreak[^"]*")[^>]*>',
  caseSensitive: false,
);
final _titleAttrRegex = RegExp(r'title\s*=\s*"([^"]*)"', caseSensitive: false);
final _ariaAttrRegex =
    RegExp(r'aria-label\s*=\s*"([^"]*)"', caseSensitive: false);
final _idAttrRegex = RegExp(r'id\s*=\s*"([^"]*)"', caseSensitive: false);
final _idNoiseRegex = RegExp(r'^(page|pg|p)[_\-]?', caseSensitive: false);

/// Rewrite EPUB page-break anchors as `[Pg N]` markers, before tags are
/// stripped, so EPUB and plain text share one path.
///
/// Only books carrying a print-edition mapping have these; most converted
/// EPUBs do not, and for those there is no page to navigate to.
String markPageBreaksInHtml(String html) =>
    html.replaceAllMapped(_pagebreakTagRegex, (m) {
      final tag = m.group(0)!;
      final label = _titleAttrRegex.firstMatch(tag)?.group(1) ??
          _ariaAttrRegex.firstMatch(tag)?.group(1) ??
          _idAttrRegex.firstMatch(tag)?.group(1);
      if (label == null) return ' ';
      final cleaned = label.replaceFirst(_idNoiseRegex, '').trim();
      return cleaned.isEmpty ? ' ' : '\n${pageMarkerFor(cleaned)}\n';
    });

/// Chunks with their page anchors lifted out.
class PagedChunks {
  const PagedChunks({
    required this.chunks,
    required this.pageChunkStarts,
    required this.chunkPages,
  });

  /// The chunks, with every marker removed — nothing here is ever spoken.
  final List<String> chunks;

  /// Normalised page label -> the chunk that page begins at.
  final Map<String, int> pageChunkStarts;

  /// The page in force at each chunk, or null before the first anchor.
  final List<String?> chunkPages;

  bool get hasPages => pageChunkStarts.isNotEmpty;

  /// Page labels in reading order.
  List<String> get pageLabels => pageChunkStarts.keys.toList();

  /// The chunk where [label] begins, or null if the book has no such page.
  int? chunkForPage(String label) => pageChunkStarts[normalizePageLabel(label)];

  /// The page showing at [chunkIndex], or null.
  String? pageAt(int chunkIndex) =>
      chunkIndex >= 0 && chunkIndex < chunkPages.length
          ? chunkPages[chunkIndex]
          : null;
}

/// Lift `[Pg N]` markers out of [chunks], recording where each page begins.
///
/// A marker on its own becomes no chunk at all; a marker embedded in one is
/// removed from the text and anchors that chunk. Either way the marker is gone
/// before anything reaches a speech engine.
PagedChunks extractPageAnchors(List<String> chunks) {
  final out = <String>[];
  final pages = <String?>[];
  final starts = <String, int>{};
  String? current;

  for (final chunk in chunks) {
    final matches = _markerRegex.allMatches(chunk).toList();
    if (matches.isNotEmpty) {
      current = normalizePageLabel(matches.first.group(1)!);
      final stripped =
          chunk.replaceAll(_markerRegex, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      // A marker alone on a line contributes no speech; the page it names
      // begins at whatever comes next.
      starts.putIfAbsent(current, () => out.length);
      if (stripped.isEmpty) continue;
      out.add(stripped);
      pages.add(current);
      continue;
    }
    out.add(chunk);
    pages.add(current);
  }

  return PagedChunks(chunks: out, pageChunkStarts: starts, chunkPages: pages);
}

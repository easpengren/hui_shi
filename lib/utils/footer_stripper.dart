/// Remove running headers / footers / page-number lines from per-page PDF text.
///
/// PDF text extraction yields one string per page, and each page still carries
/// its running header and footer — the book/chapter title and the page number
/// that repeat on nearly every page. Those lines sit in the top/bottom "band"
/// of the page and recur (verbatim, modulo the page number) across many pages,
/// so we detect them by frequency and drop them, leaving the body text intact.
/// Standalone page-number lines in the band are dropped even if they don't
/// repeat verbatim (they never do — the number changes every page).
///
/// Pure and deterministic so it can be unit-tested without a real PDF. Operates
/// per-batch: a caller that loads a PDF in chunks can strip each batch
/// independently, since the header/footer recurs within any batch of pages.
List<String> stripRepeatedHeadersFooters(
  List<String> pages, {
  int bandLines = 1,
  double minFraction = 0.3,
  int minPages = 3,
}) {
  // Too few pages to tell a running header from ordinary text — leave as-is.
  if (pages.length < minPages) return pages;

  final perPageLines = [
    for (final page in pages) page.split('\n').map((l) => l.trim()).toList(),
  ];

  // Count how often each normalized band line recurs across pages.
  final bandCounts = <String, int>{};
  for (final lines in perPageLines) {
    for (final i in _bandIndices(lines, bandLines)) {
      final norm = _normalizeLine(lines[i]);
      if (norm.isNotEmpty) bandCounts[norm] = (bandCounts[norm] ?? 0) + 1;
    }
  }

  final threshold =
      (pages.length * minFraction).ceil().clamp(minPages, pages.length);
  final repeated = {
    for (final e in bandCounts.entries)
      if (e.value >= threshold) e.key,
  };

  // Rebuild each page, dropping band lines that repeat or are page numbers.
  final out = <String>[];
  for (final lines in perPageLines) {
    final band = _bandIndices(lines, bandLines);
    final kept = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) {
        kept.add(line); // preserve blank lines (paragraph breaks)
        continue;
      }
      if (band.contains(i) &&
          (repeated.contains(_normalizeLine(line)) || _isPageNumber(line))) {
        continue; // running header / footer / page number
      }
      kept.add(line);
    }
    out.add(kept.join('\n'));
  }
  return out;
}

/// Indices of the first [bandLines] and last [bandLines] non-empty lines — the
/// top and bottom edges of the page where headers/footers live.
Set<int> _bandIndices(List<String> lines, int bandLines) {
  final nonEmpty = [
    for (var i = 0; i < lines.length; i++)
      if (lines[i].isNotEmpty) i,
  ];
  final band = <int>{};
  for (var k = 0; k < bandLines && k < nonEmpty.length; k++) {
    band.add(nonEmpty[k]); // from the top
    band.add(nonEmpty[nonEmpty.length - 1 - k]); // from the bottom
  }
  return band;
}

/// Normalize a line for recurrence matching: digits → '#' (so "Page 3" and
/// "Page 4" collapse to one running footer), lowercased, whitespace-collapsed.
String _normalizeLine(String line) => line
    .toLowerCase()
    .replaceAll(RegExp(r'\d+'), '#')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

final _pageNumberRegex = RegExp(
  r'^(page\s*)?\d+(\s*(of|/|\||-|–|—)\s*\d+)?$',
  caseSensitive: false,
);

/// A standalone page-number line: "3", "Page 3", "3 of 200", "3 / 200",
/// "3-200". Requires a digit, so body words never match.
bool _isPageNumber(String line) {
  final t = line.trim();
  if (t.isEmpty || t.length > 20 || !t.contains(RegExp(r'\d'))) return false;
  return _pageNumberRegex.hasMatch(t);
}

// Geometry-aware reflow of a PDF text layer into clean reading paragraphs.
//
// PDF gives us positioned text fragments, not paragraphs. Using their
// coordinates we can do this properly: group fragments into lines by vertical
// position, drop headers/footers/page-numbers by where they sit + how often
// they repeat, then rejoin wrapped lines into paragraphs using the real signals
// — vertical gaps between lines, first-line indentation, and font-size jumps
// for headings — de-hyphenating across line breaks along the way.
//
// Works on plain [PdfFragment]/[PdfLine] data (decoupled from pdfrx) so it can
// be unit-tested without pdfium, which only loads in a real build.

import 'dart:math' as math;

/// A positioned run of text from the PDF, in PDF page coordinates where y
/// increases upward (so [top] >= [bottom]).
class PdfFragment {
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  const PdfFragment(this.text, this.left, this.top, this.right, this.bottom);
}

/// One visual line: its text and bounding box.
class PdfLine {
  final String text;
  final double left;
  final double right;
  final double top;
  final double bottom;
  const PdfLine(this.text, this.left, this.right, this.top, this.bottom);
  double get height => top - bottom;
}

final _pureNumberLine = RegExp(r'^\d{1,4}$');
final _romanNumeralLine = RegExp(r'^[ivxlcdm]{2,7}$', caseSensitive: false);
final _pageLabelLine = RegExp(r'^(page|p\.?)\s*\d{1,4}$', caseSensitive: false);

bool isPageNumberLine(String s) =>
    _pureNumberLine.hasMatch(s) ||
    _romanNumeralLine.hasMatch(s) ||
    _pageLabelLine.hasMatch(s);

final _leadingPageNum = RegExp(r'^(\d{1,4}|[ivxlcdm]{1,7})\s+', caseSensitive: false);
final _trailingPageNum = RegExp(r'\s+(\d{1,4}|[ivxlcdm]{1,7})$', caseSensitive: false);

/// Drop a leading/trailing page-number token so a running header carrying the
/// page number on the same line (e.g. "6 CAMPAIGNING TO ENGAGE AND WIN") still
/// matches the bare header.
String _stripEdgePageNumbers(String s) => s
    .trim()
    .replaceFirst(_leadingPageNum, '')
    .replaceFirst(_trailingPageNum, '')
    .trim();

/// Group positioned fragments into visual lines by vertical position, then
/// order each line's fragments left-to-right.
List<PdfLine> groupFragmentsIntoLines(List<PdfFragment> fragments) {
  final items = fragments
      .where((f) => f.text.replaceAll('\n', ' ').trim().isNotEmpty)
      .toList();
  if (items.isEmpty) return const [];
  // Reading order: top of page first (higher `top`), then left-to-right.
  items.sort((a, b) {
    final dt = b.top.compareTo(a.top);
    return dt != 0 ? dt : a.left.compareTo(b.left);
  });

  final lines = <PdfLine>[];
  final current = <PdfFragment>[];
  double lineTop = 0, lineBottom = 0;

  void flush() {
    if (current.isEmpty) return;
    current.sort((a, b) => a.left.compareTo(b.left));
    final sb = StringBuffer();
    for (var i = 0; i < current.length; i++) {
      if (i > 0) {
        final gap = current[i].left - current[i - 1].right;
        final prev = current[i - 1].text;
        // Insert a space when there's a real horizontal gap and neither side
        // already has whitespace.
        if (gap > 1.0 && !prev.endsWith(' ') && !current[i].text.startsWith(' ')) {
          sb.write(' ');
        }
      }
      sb.write(current[i].text.replaceAll('\n', ' '));
    }
    var left = current.first.left, right = current.first.right;
    var top = current.first.top, bottom = current.first.bottom;
    for (final f in current) {
      left = math.min(left, f.left);
      right = math.max(right, f.right);
      top = math.max(top, f.top);
      bottom = math.min(bottom, f.bottom);
    }
    final text = sb.toString().replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    if (text.isNotEmpty) lines.add(PdfLine(text, left, right, top, bottom));
    current.clear();
  }

  for (final f in items) {
    if (current.isEmpty) {
      current.add(f);
      lineTop = f.top;
      lineBottom = f.bottom;
      continue;
    }
    final fCenter = (f.top + f.bottom) / 2;
    final curCenter = (lineTop + lineBottom) / 2;
    final tolerance = (lineTop - lineBottom).abs() * 0.5 + 1.0; // ~half line
    if ((fCenter - curCenter).abs() <= tolerance) {
      current.add(f);
      lineTop = math.max(lineTop, f.top);
      lineBottom = math.min(lineBottom, f.bottom);
    } else {
      flush();
      current.add(f);
      lineTop = f.top;
      lineBottom = f.bottom;
    }
  }
  flush();
  return lines;
}

/// Lines that repeat at the top/bottom of many pages are running
/// headers/footers — collect their text so the body reflow can drop them.
Set<String> detectRunningHeaders(List<List<PdfLine>> pages) {
  if (pages.length < 4) return <String>{};
  final counts = <String, int>{};
  for (final lines in pages) {
    if (lines.isEmpty) continue;
    final edges = <String>{
      ...lines.take(2).map((l) => _stripEdgePageNumbers(l.text)),
      ...lines.reversed.take(2).map((l) => _stripEdgePageNumbers(l.text)),
    };
    for (final e in edges) {
      if (e.isNotEmpty && e.length <= 80) counts[e] = (counts[e] ?? 0) + 1;
    }
  }
  // Require solid repetition, but cap the bar at 6 pages so per-chapter running
  // headers (which repeat on a chapter's worth of pages, well under 30% of a
  // long book) are still caught. Only edge lines are considered, so body text
  // that happens to repeat is never stripped.
  final threshold = (pages.length * 0.3).ceil().clamp(3, 6);
  return counts.entries
      .where((e) => e.value >= threshold)
      .map((e) => e.key)
      .toSet();
}

double _median(List<double> xs) {
  if (xs.isEmpty) return 0;
  final s = [...xs]..sort();
  return s[s.length ~/ 2];
}

/// Rejoin a page's lines into paragraphs using geometry: vertical gaps,
/// first-line indentation, and font-size jumps (headings).
List<String> reflowLines(
  List<PdfLine> lines, {
  Set<String> runningHeaders = const {},
}) {
  final body = <PdfLine>[];
  for (final l in lines) {
    final t = l.text.trim();
    if (t.isEmpty || isPageNumberLine(t)) continue;
    final norm = _stripEdgePageNumbers(t);
    if (norm.isEmpty || runningHeaders.contains(norm)) continue;
    body.add(l);
  }
  if (body.isEmpty) return const [];

  final medHeight = _median(body.map((l) => l.height).toList());
  final gaps = <double>[
    for (var i = 1; i < body.length; i++) body[i - 1].top - body[i].top,
  ];
  final medGap = gaps.isEmpty ? medHeight * 1.2 : _median(gaps);
  final bodyLeft = body.map((l) => l.left).reduce(math.min);

  final paragraphs = <String>[];
  final buf = StringBuffer();
  void flush() {
    final p = buf.toString().replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    if (p.isNotEmpty) paragraphs.add(p);
    buf.clear();
  }

  for (var i = 0; i < body.length; i++) {
    final line = body[i];
    final t = line.text.trim();
    final isHeading = (medHeight > 0 && line.height > medHeight * 1.35) ||
        (t.length <= 60 && t == t.toUpperCase() && RegExp(r'[A-Z]').hasMatch(t));

    if (i > 0) {
      final gap = body[i - 1].top - line.top;
      final newByGap = medGap > 0 && gap > medGap * 1.6;
      final newByIndent =
          medHeight > 0 && line.left > bodyLeft + medHeight * 0.8;
      if (isHeading || newByGap || newByIndent) flush();
    }

    if (isHeading) {
      flush();
      paragraphs.add(t);
      continue;
    }

    if (buf.isEmpty) {
      buf.write(t);
    } else {
      final prev = buf.toString();
      if (prev.endsWith('-') && RegExp(r'^[a-z]').hasMatch(t)) {
        buf.clear();
        buf.write(prev.substring(0, prev.length - 1) + t); // de-hyphenate
      } else {
        buf.write(' ');
        buf.write(t);
      }
    }
  }
  flush();
  return paragraphs;
}

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

// A standalone short number token (page number) anywhere in a line. Arabic
// only — matching roman numerals here would eat real words ("did", "mill", …).
final _embeddedNumToken = RegExp(r'(?<!\d)\d{1,4}(?!\d)');

/// Normalize a running-header/footer candidate so lines that differ ONLY by a
/// page number collapse to one key. Strips standalone page-number tokens
/// wherever they sit — not just the edges — so a running head like
/// "6 CAMPAIGNING TO ENGAGE AND WIN" and, critically, an export footer with the
/// page number embedded mid-line (e.g. an InDesign
/// "<file>.indd 25   21/05/15 3:00 PM" footer) both reduce to a stable key that
/// repeats across pages and can be detected + dropped.
String _normalizeRunningLine(String s) => s
    .replaceAll(_embeddedNumToken, ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
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
      ...lines.take(2).map((l) => _normalizeRunningLine(l.text)),
      ...lines.reversed.take(2).map((l) => _normalizeRunningLine(l.text)),
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
    final norm = _normalizeRunningLine(t);
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

/// A chapter derived from the text layer: a title and its body paragraphs.
class ReflowChapter {
  final String title;
  final List<String> paragraphs;
  const ReflowChapter(this.title, this.paragraphs);
}

/// Body lines of a page: text, minus page numbers and running headers/footers.
List<PdfLine> _bodyLines(List<PdfLine> lines, Set<String> running) => [
      for (final l in lines)
        if (l.text.trim().isNotEmpty &&
            !isPageNumberLine(l.text.trim()) &&
            _normalizeRunningLine(l.text.trim()).isNotEmpty &&
            !running.contains(_normalizeRunningLine(l.text.trim())))
          l,
    ];

/// Derive chapters from font-size headings, for books with NO embedded outline.
/// A page whose first body line is clearly larger than the body median starts a
/// new chapter — books almost always begin a chapter on a fresh page. Returns
/// null when no sensible structure emerges (fewer than 2 headings, or a heading
/// on most pages) so the caller can fall back to one section per page.
///
/// Reflow stays per-page (vertical gaps are page-relative); this only groups the
/// resulting paragraphs under the detected chapter titles.
List<ReflowChapter>? chaptersByHeading(
  List<List<PdfLine>> pages, {
  Set<String> runningHeaders = const {},
}) {
  final bodies = [for (final p in pages) _bodyLines(p, runningHeaders)];
  final heights = [for (final b in bodies) for (final l in b) l.height];
  if (heights.isEmpty) return null;
  final med = _median(heights);
  if (med <= 0) return null;

  bool startsChapter(List<PdfLine> body) {
    if (body.isEmpty) return false;
    final l = body.first;
    final t = l.text.trim();
    return l.height > med * 1.4 && t.length >= 2 && t.length <= 80;
  }

  final starts = <int, String>{}; // page index -> chapter title
  for (var p = 0; p < bodies.length; p++) {
    if (startsChapter(bodies[p])) starts[p] = bodies[p].first.text.trim();
  }
  if (starts.length < 2 || starts.length > (pages.length * 0.8).ceil()) {
    return null; // no usable chapter structure
  }

  final pageParas = [
    for (final b in bodies) reflowLines(b, runningHeaders: runningHeaders)
  ];

  final chapters = <ReflowChapter>[];
  var curTitle = '';
  final curParas = <String>[];
  void flush() {
    if (curParas.isEmpty && curTitle.isEmpty) return;
    chapters.add(ReflowChapter(
        curTitle.isEmpty ? 'Beginning' : curTitle, List.of(curParas)));
    curParas.clear();
    curTitle = '';
  }

  for (var p = 0; p < pageParas.length; p++) {
    final paras = pageParas[p];
    if (starts.containsKey(p)) {
      flush();
      curTitle = starts[p]!;
      // The heading is the page's first paragraph; drop it so it isn't repeated
      // under the chapter title.
      curParas.addAll(paras.isNotEmpty && paras.first.trim() == curTitle
          ? paras.skip(1)
          : paras);
    } else {
      curParas.addAll(paras);
    }
  }
  flush();
  final out = chapters.where((c) => c.paragraphs.isNotEmpty).toList();
  return out.isEmpty ? null : out;
}

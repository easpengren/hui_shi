/// Navigating by the pages of the physical book.
///
/// A page number is **metadata, not a measurement**. It cannot be derived from
/// the text: two editions of the same work break pages differently, and a
/// reflowable file has no pages at all. So this never invents one. Pages exist
/// only where the source carried them, and a book without them reports that
/// honestly rather than offering a number that matches nothing on a shelf.
///
/// Where they come from, by format:
///
///  * **PDF** — the printed number on each page, which `pdf_reflow` already
///    locates in order to delete it. Captured before it is discarded, so
///    "page 213" means the book's 213, not the 213th sheet of the file.
///  * **EPUB** — `epub:type="pagebreak"` anchors, present in books that carry
///    a print-edition mapping and absent in most converted ones.
///  * **TXT** — `[Pg 45]` markers from the scanned original. Measured against
///    five Project Gutenberg books across three URL styles: **none had them.**
///    Current Gutenberg plain text strips these, so this path is supported but
///    will rarely fire.
///
/// Anchors are recorded against *paragraph* positions upstream and translated
/// to chunk positions here, because chunking is not stable — a long paragraph
/// splits, boilerplate is dropped — and an anchor stored as a chunk index would
/// rot the moment any of that changed.
library;

import '../models/document.dart';
import 'chunking_service.dart';
import 'front_matter.dart';
import 'text_cleaner.dart';

// ── Extraction ───────────────────────────────────────────────────────────────

/// An inline page marker as found in scanned plain text: `[Pg 45]`, `[Page 45]`.
///
/// `{45}` is deliberately not matched — braces carry too much other meaning to
/// risk swallowing content for a marker style that is already rare.
final _inlineMarkerRegex =
    RegExp(r'\[\s*(?:pg|page)\.?\s*([0-9ivxlcdm]{1,6})\s*\]', caseSensitive: false);

/// Strip inline page markers from [paragraphs], reporting where they were.
///
/// Returns the cleaned paragraphs and a map of paragraph index -> page label.
/// A marker anywhere in a paragraph is treated as beginning that paragraph:
/// the page turned partway through a sentence, and the reader wants the
/// sentence, not the fragment after the break.
(List<String>, Map<int, String>) extractInlinePageMarkers(
    List<String> paragraphs) {
  final cleaned = <String>[];
  final anchors = <int, String>{};

  for (var i = 0; i < paragraphs.length; i++) {
    final matches = _inlineMarkerRegex.allMatches(paragraphs[i]).toList();
    if (matches.isNotEmpty) {
      anchors[i] = normalizePageLabel(matches.first.group(1)!);
    }
    cleaned.add(paragraphs[i]
        .replaceAll(_inlineMarkerRegex, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim());
  }
  return (cleaned, anchors);
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
final _idNoiseRegex =
    RegExp(r'^(page|pg|p)[_\-]?', caseSensitive: false);

/// Rewrite EPUB page-break anchors as inline `[Pg N]` markers.
///
/// Run before tags are stripped, so the anchors survive into the text and can
/// be picked up by [extractInlinePageMarkers] — one extraction path for both
/// EPUB and plain text rather than two.
///
/// Only books carrying a print-edition mapping have these. Most converted
/// EPUBs do not, and for those there is no page to navigate to.
String markPageBreaksInHtml(String html) =>
    html.replaceAllMapped(_pagebreakTagRegex, (m) {
      final tag = m.group(0)!;
      final label = _titleAttrRegex.firstMatch(tag)?.group(1) ??
          _ariaAttrRegex.firstMatch(tag)?.group(1) ??
          _idAttrRegex.firstMatch(tag)?.group(1);
      if (label == null) return ' ';
      final cleaned = label.replaceFirst(_idNoiseRegex, '').trim();
      return cleaned.isEmpty ? ' ' : ' [Pg $cleaned] ';
    });

/// Carry a page sequence across pages that print no number.
///
/// Chapter openings, plates and full-page illustrations routinely omit the
/// folio while still counting. Where the previous page had an arabic number,
/// the next is assumed to be one more; anything detected on the page itself
/// wins over the assumption.
///
/// The failure this accepts: an unnumbered insert that does *not* count will
/// shift everything after it by one until the next printed number corrects it.
List<String?> fillPageLabels(List<String?> detected) {
  final out = List<String?>.from(detected);
  for (var i = 1; i < out.length; i++) {
    if (out[i] != null) continue;
    final previous = int.tryParse(out[i - 1] ?? '');
    if (previous != null) out[i] = '${previous + 1}';
  }
  return out;
}

/// A document reduced to chunks, with the structure needed to navigate it.
class ChunkedDocument {
  const ChunkedDocument({
    required this.chunks,
    required this.chapterChunkStarts,
    required this.pageChunkStarts,
    required this.chunkPages,
  });

  /// The text, one chunk per paragraph (long paragraphs split).
  final List<String> chunks;

  /// Index into [chunks] where each chapter begins.
  final List<int> chapterChunkStarts;

  /// Normalised page label -> the chunk that page begins at, in reading order.
  final Map<String, int> pageChunkStarts;

  /// The page in force at each chunk, or null before the first anchor.
  final List<String?> chunkPages;

  /// Whether this document carries real page numbers at all.
  bool get hasPages => pageChunkStarts.isNotEmpty;

  /// Page labels in reading order, for a picker.
  List<String> get pageLabels => pageChunkStarts.keys.toList();

  /// The chunk where [label] begins, or null if the book has no such page.
  int? chunkForPage(String label) => pageChunkStarts[normalizePageLabel(label)];

  /// The page showing at [chunkIndex], or null.
  String? pageAt(int chunkIndex) =>
      chunkIndex >= 0 && chunkIndex < chunkPages.length
          ? chunkPages[chunkIndex]
          : null;
}

final _labelNoiseRegex = RegExp(r'^(page|pg|p)\.?\s*', caseSensitive: false);

/// Compare page labels forgivingly: "p. 12", "Page 12" and "12" are one page,
/// and roman numerals match regardless of case.
String normalizePageLabel(String label) =>
    label.trim().replaceFirst(_labelNoiseRegex, '').trim().toLowerCase();

/// Build the chunk list and its navigation structure.
///
/// [pageStarts] maps a **global paragraph index** — counted across all
/// chapters, before any filtering — to the page label beginning at it.
ChunkedDocument buildChunkedDocument({
  required List<Chapter> chapters,
  Map<int, String> pageStarts = const <int, String>{},
}) {
  // Flatten, remembering which chapter each paragraph came from.
  final paragraphs = <String>[];
  final paragraphChapter = <int>[];
  for (var c = 0; c < chapters.length; c++) {
    for (final p in chapters[c].paragraphs) {
      paragraphs.add(p);
      paragraphChapter.add(c);
    }
  }

  // Chunk each paragraph separately so an anchor keeps its exact position.
  // Equivalent to chunking the joined text: cleanText splits on blank lines,
  // which is where the joins were.
  final rawChunks = <String>[];
  final rawChapter = <int>[];
  final rawPage = <String?>[];
  String? currentPage;

  for (final index in gutenbergBodyIndices(paragraphs)) {
    final label = pageStarts[index];
    if (label != null) currentPage = normalizePageLabel(label);
    for (final chunk in chunkText(cleanText(paragraphs[index]))) {
      rawChunks.add(chunk);
      rawChapter.add(paragraphChapter[index]);
      rawPage.add(currentPage);
    }
  }

  // Boilerplate is judged over the whole document, so its edge window still
  // means the edges of the book rather than of a paragraph.
  final kept = keptChunkIndices(rawChunks);

  final chunks = <String>[];
  final chunkPages = <String?>[];
  final pageChunkStarts = <String, int>{};
  final firstChunkOfChapter = <int, int>{};

  for (final index in kept) {
    firstChunkOfChapter.putIfAbsent(rawChapter[index], () => chunks.length);
    final page = rawPage[index];
    if (page != null) pageChunkStarts.putIfAbsent(page, () => chunks.length);
    chunks.add(rawChunks[index]);
    chunkPages.add(page);
  }

  // Every chapter needs a start, including any whose content was all dropped;
  // those point at where the next surviving content begins.
  final chapterChunkStarts = <int>[];
  for (var c = 0; c < chapters.length; c++) {
    chapterChunkStarts.add(firstChunkOfChapter[c] ?? chunks.length);
  }

  return ChunkedDocument(
    chunks: chunks,
    chapterChunkStarts: chapterChunkStarts,
    pageChunkStarts: pageChunkStarts,
    chunkPages: chunkPages,
  );
}

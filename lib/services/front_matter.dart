/// Dropping the parts of a book that are not the book.
///
/// Copyright pages, ISBNs, printing histories and distribution licences are
/// legally required in print and worthless read aloud. A Project Gutenberg
/// plain text is the extreme case: the header and trailing licence come to
/// **19,305 characters** on *The Art of War* — 5.8% of the file, and about
/// twenty-five minutes of speech before and after the actual work.
///
/// Two mechanisms, because there are two kinds of boilerplate:
///
///  * [stripGutenbergWrapper] is exact. Gutenberg delimits the work with
///    machine-readable markers, so the wrapper can be removed with certainty
///    and no heuristics.
///  * [dropBoilerplate] is a heuristic for publisher front and back matter,
///    which has no markers. It is deliberately timid — see the guards on
///    [isPublisherBoilerplate].
///
/// What is **not** dropped: the title page, the byline, and the dedication.
/// Those are part of the book as read, and "credits" in the sense of
/// authorship is orienting rather than noise. Only production and legal
/// apparatus goes.
library;

final _gutenbergStart =
    RegExp(r'\*\*\*\s*START OF (THE|THIS) PROJECT GUTENBERG.*?\*\*\*',
        caseSensitive: false, dotAll: true);
final _gutenbergEnd =
    RegExp(r'\*\*\*\s*END OF (THE|THIS) PROJECT GUTENBERG.*?\*\*\*',
        caseSensitive: false, dotAll: true);

/// Return only the work itself — the span between the Gutenberg markers.
///
/// Falls back to the whole text when a marker is absent, so a non-Gutenberg
/// document passes through untouched. Mirrors `strip_boilerplate` in the
/// confucius ingest script, which has read several dozen of these files.
String stripGutenbergWrapper(String text) {
  final start = _gutenbergStart.firstMatch(text);
  var body = start == null ? text : text.substring(start.end);
  final end = _gutenbergEnd.firstMatch(body);
  if (end != null) body = body.substring(0, end.start);
  return body.trim();
}

/// Phrases that only appear on a copyright or production page.
final _boilerplateMarkers = <RegExp>[
  RegExp(r'\ball rights reserved\b', caseSensitive: false),
  RegExp(r'(copyright\s*(©|\(c\)))|(©\s*\d{4})|(\(c\)\s*\d{4})',
      caseSensitive: false),
  RegExp(r'\be?ISBN\b', caseSensitive: false),
  RegExp(r'library of congress catalog', caseSensitive: false),
  RegExp(r'british library catalogu', caseSensitive: false),
  RegExp(r'CIP catalogue record', caseSensitive: false),
  RegExp(r'no part of this (book|publication|work|ebook)',
      caseSensitive: false),
  RegExp(r'\bprinted (and bound )?in\b', caseSensitive: false),
  RegExp(r'\bmanufactured in\b', caseSensitive: false),
  RegExp(r'\bfirst published\b', caseSensitive: false),
  RegExp(r'moral right of the author', caseSensitive: false),
  RegExp(r'\bproject gutenberg\b', caseSensitive: false),
  RegExp(r'\bcover (design|art|illustration) by\b', caseSensitive: false),
  RegExp(r'\btypeset (in|by)\b', caseSensitive: false),
  RegExp(r'for information,? address\b', caseSensitive: false),
  RegExp(r'\bpublished by arrangement with\b', caseSensitive: false),
  // A printing-history number line: "10 9 8 7 6 5 4 3 2 1".
  RegExp(r'^\s*\d{1,2}(\s+\d{1,2}){4,}\s*$'),
];

/// Longest a paragraph can be and still be treated as boilerplate.
///
/// A copyright notice is a few lines. A chapter *about* copyright law that
/// happens to contain "all rights reserved" is not, and this is what keeps it
/// from being silently deleted.
const _boilerplateMaxLength = 500;

/// True when [paragraph] is publisher apparatus rather than the work.
bool isPublisherBoilerplate(String paragraph) {
  final text = paragraph.trim();
  if (text.isEmpty || text.length > _boilerplateMaxLength) return false;
  return _boilerplateMarkers.any((re) => re.hasMatch(text));
}


/// A contents list: entries, not prose.
///
/// Never read aloud usefully — it is a navigation aid for the eye, and spoken
/// it is a minute of chapter titles and numbers before the book starts. It is
/// detected separately from copyright apparatus because it is *long*, so the
/// length ceiling in [isPublisherBoilerplate] would never catch it. On the
/// Project Gutenberg Art of War the contents block survives as a single
/// 561-character paragraph.
///
/// Evidence required, because a chapter that merely discusses chapters must
/// survive: an explicit "Contents" opening, or several chapter-like entries,
/// or several dot-leader page references.
bool isTableOfContents(String paragraph) {
  final text = paragraph.trim();
  if (text.isEmpty) return false;

  final lower = text.toLowerCase();
  if (RegExp(r'^(table of )?contents\b').hasMatch(lower)) return true;

  // "Chapter I.", "Chapter 4", "CHAPTER XII" — three or more in one block is a
  // list of chapters, not a sentence about one.
  final entries =
      RegExp(r'\bchapter\s+[ivxlcdm\d]', caseSensitive: false).allMatches(text).length;
  if (entries >= 3) return true;

  // "Laying Plans .......... 1"
  final leaders = RegExp(r'\.{3,}\s*\d{1,4}').allMatches(text).length;
  if (leaders >= 3) return true;

  return false;
}

/// How many chunks from each end are eligible to be dropped.
///
/// Front and back matter live at the edges. Restricting the search there means
/// a false positive cannot delete text from the middle of a book, which is the
/// failure that would actually matter.
///
/// Wider than it looks: chunks here are sentences, not paragraphs, so eighty of
/// them is a couple of pages rather than a couple of chapters.
const _edgeWindow = 80;

/// Indices of [chunks] to keep — the index-preserving form of
/// [dropBoilerplate], for callers that must remap positions alongside the text
/// (page anchors, chapter starts).
List<int> keptChunkIndices(List<String> chunks, {int edgeWindow = _edgeWindow}) {
  final kept = <int>[];
  for (var i = 0; i < chunks.length; i++) {
    final nearEdge = i < edgeWindow || i >= chunks.length - edgeWindow;
    if (nearEdge &&
        (isPublisherBoilerplate(chunks[i]) || isTableOfContents(chunks[i]))) {
      continue;
    }
    kept.add(i);
  }
  // A document that is *entirely* boilerplate is far more likely to be a
  // misjudgement than a book with no content. Hand it back untouched.
  if (kept.isEmpty) return List<int>.generate(chunks.length, (i) => i);
  return kept;
}

/// Remove publisher boilerplate near the start and end of [chunks].
List<String> dropBoilerplate(List<String> chunks, {int edgeWindow = _edgeWindow}) {
  if (chunks.isEmpty) return chunks;
  return [
    for (final i in keptChunkIndices(chunks, edgeWindow: edgeWindow)) chunks[i],
  ];
}

/// Indices of [paragraphs] that lie within the Project Gutenberg markers.
///
/// The paragraph-level counterpart of [stripGutenbergWrapper], needed because
/// page anchors are recorded against paragraph positions: dropping the wrapper
/// by rewriting the text would leave every anchor pointing at the wrong place.
List<int> gutenbergBodyIndices(List<String> paragraphs) {
  var first = 0;
  var last = paragraphs.length;
  for (var i = 0; i < paragraphs.length; i++) {
    if (_gutenbergStart.hasMatch(paragraphs[i])) {
      first = i + 1;
      break;
    }
  }
  for (var i = first; i < paragraphs.length; i++) {
    if (_gutenbergEnd.hasMatch(paragraphs[i])) {
      last = i;
      break;
    }
  }
  if (first >= last) return List<int>.generate(paragraphs.length, (i) => i);
  return [for (var i = first; i < last; i++) i];
}

/// A line that belongs to a contents list rather than the book.
///
/// Only ever consulted *inside* a contents region — on its own, "Introduction,
/// 3" is too weak a signal to delete anything.
bool looksLikeTocEntry(String chunk) {
  final text = chunk.trim();
  if (text.isEmpty || text.length > 90) return false;
  // "Introduction, 3" / "The Model .... 24" / "Chapter One 47"
  if (RegExp(r'[.,\s]\s*\d{1,4}$').hasMatch(text)) return true;
  // "1. The Game of Wei-ch'i" with no page number.
  if (RegExp(r"^(chapter\s+)?[ivxlcdm\d]{1,5}[.)]\s+\S", caseSensitive: false)
      .hasMatch(text)) {
    return true;
  }
  return false;
}

/// A heading that opens a contents list.
bool isContentsHeading(String chunk) => RegExp(r'^(table of )?contents\b',
    caseSensitive: false).hasMatch(chunk.trim());

/// Prose: long enough, and punctuated like a sentence. Ends a contents region.
bool _isProse(String chunk) {
  final text = chunk.trim();
  return text.length > 120 && RegExp(r'[.!?]$').hasMatch(text);
}

/// Publisher lines a copyright page carries that name no ISBN or ©.
final _publisherLineRegex = RegExp(
  r'\bpublished (simultaneously|by|in)\b'
  r'|\buniversity press\b'
  r'|\ball rights reserved\b',
  caseSensitive: false,
);

/// Remove a book's front and back matter.
///
/// Region-aware, which per-chunk filtering cannot be: chunks here are
/// sentences, so a copyright page or a contents list is many chunks and only
/// the one carrying "©" or "Contents" matches a pattern on its own. The rest —
/// "Published simultaneously in Canada", "1. The Game of Wei-ch'i, 11" — look
/// like ordinary short lines unless you know what preceded them.
///
/// So a contents *heading* opens a region, and every entry-shaped line after it
/// goes until real prose or a section heading arrives. That is how a reader
/// skips a contents list: not by recognising each line, but by knowing where
/// the list started and where it stopped.
///
/// [leadWindow] is generous because front matter is: title, copyright,
/// dedication, contents and a preface can run well past a hundred sentences.
/// [tailWindow] is tighter — back matter is usually just a colophon.
List<String> dropFrontMatter(
  List<String> chunks, {
  int leadWindow = 150,
  int tailWindow = 60,
}) {
  if (chunks.isEmpty) return chunks;

  final kept = <String>[];
  var inContents = false;

  for (var i = 0; i < chunks.length; i++) {
    final chunk = chunks[i];
    final nearFront = i < leadWindow;
    final nearBack = i >= chunks.length - tailWindow;

    if (nearFront) {
      if (isContentsHeading(chunk) || isTableOfContents(chunk)) {
        inContents = true;
        continue;
      }
      if (inContents) {
        if (looksLikeTocEntry(chunk)) continue;
        // Anything else ends the list — the book has started.
        if (_isProse(chunk) || chunk.trim().length > 90) inContents = false;
        if (looksLikeTocEntry(chunk)) continue;
      }
      if (isPublisherBoilerplate(chunk) ||
          _publisherLineRegex.hasMatch(chunk)) {
        continue;
      }
    } else if (nearBack &&
        (isPublisherBoilerplate(chunk) || isTableOfContents(chunk))) {
      continue;
    }

    kept.add(chunk);
  }

  // A document that is entirely front matter is a misjudgement, not a book
  // with no content.
  return kept.isEmpty ? chunks : kept;
}

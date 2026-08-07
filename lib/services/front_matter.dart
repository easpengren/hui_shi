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

/// How many chunks from each end are eligible to be dropped.
///
/// Front and back matter live at the edges. Restricting the search there means
/// a false positive cannot delete a paragraph from the middle of a book, which
/// is the failure that would actually matter.
const _edgeWindow = 30;

/// Remove publisher boilerplate near the start and end of [chunks].
List<String> dropBoilerplate(List<String> chunks, {int edgeWindow = _edgeWindow}) {
  if (chunks.isEmpty) return chunks;

  final kept = <String>[];
  for (var i = 0; i < chunks.length; i++) {
    final nearEdge = i < edgeWindow || i >= chunks.length - edgeWindow;
    if (nearEdge && isPublisherBoilerplate(chunks[i])) continue;
    kept.add(chunks[i]);
  }

  // A document that is *entirely* boilerplate is far more likely to be a
  // misjudgement than a book with no content. Hand it back untouched.
  return kept.isEmpty ? chunks : kept;
}

// A parsed book with its structure preserved — the foundation for a real
// reader (chapters/TOC, per-chapter typesetting, resume) instead of one flat
// blob of text.

/// One chapter: a title and its block paragraphs (in reading order).
class Chapter {
  final String title;
  final List<String> paragraphs;

  const Chapter({required this.title, required this.paragraphs});

  /// Plain text of the chapter (paragraphs joined) — used for TTS chunking.
  String get text => paragraphs.join('\n\n');
}

/// A parsed document: an ordered list of chapters.
class BookDocument {
  final String title;
  final List<Chapter> chapters;

  const BookDocument({required this.title, required this.chapters});

  /// Whole-book plain text — bridge for the existing flat TTS chunking path
  /// until the reader works chapter-by-chapter.
  String get flatText => chapters.map((c) => c.text).join('\n\n');
}

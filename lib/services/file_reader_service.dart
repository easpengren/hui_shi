import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:epubx/epubx.dart';

import '../models/document.dart';
import 'pdf_reflow.dart';

enum SupportedFileType { txt, pdf, epub }

class FileReadResult {
  final String path;
  final String title;

  /// The document with its chapter structure preserved.
  final List<Chapter> chapters;
  final SupportedFileType type;

  const FileReadResult({
    required this.path,
    required this.title,
    required this.chapters,
    required this.type,
  });

  /// Flattened plain text — bridge for the existing TTS chunking path while the
  /// reader is migrated to render chapters directly.
  String get content => chapters.map((c) => c.text).join('\n\n');
}

class FileReaderService {
  /// Show the system file picker and return the read result, or null if
  /// the user cancelled.
  Future<FileReadResult?> pickAndRead() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'pdf', 'epub'],
    );
    if (picked == null || picked.files.single.path == null) return null;
    // Android's picker often returns a disposable cache path that's gone by the
    // next launch — so the library could never reopen the book. Copy it into the
    // app's own storage and use that durable path instead.
    final durablePath = await _persist(picked.files.single.path!);
    return _readFromPath(durablePath);
  }

  /// Copy a picked file into the app's documents dir so its path survives.
  Future<String> _persist(String srcPath) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final booksDir = Directory('${docs.path}/books')
        ..createSync(recursive: true);
      final dest = '${booksDir.path}/${srcPath.split('/').last}';
      if (dest != srcPath) await File(srcPath).copy(dest);
      return dest;
    } catch (_) {
      return srcPath; // fall back to the original path if the copy fails
    }
  }

  /// Re-read a file that is already on-device (e.g. from the library).
  Future<FileReadResult?> readFromPath(String path) => _readFromPath(path);

  Future<FileReadResult?> _readFromPath(String path) async {
    if (!File(path).existsSync()) return null;

    final filename = path.split('/').last;
    final ext = filename.split('.').last.toLowerCase();
    final titleFromFilename = filename.replaceAll(RegExp(r'\.[^.]+$'), '');

    switch (ext) {
      case 'txt':
        final raw = await File(path).readAsString();
        return FileReadResult(
          path: path,
          title: titleFromFilename,
          chapters: [Chapter(title: titleFromFilename, paragraphs: _splitParagraphs(raw))],
          type: SupportedFileType.txt,
        );
      case 'pdf':
        return FileReadResult(
          path: path,
          title: titleFromFilename,
          chapters: await _extractPdf(path),
          type: SupportedFileType.pdf,
        );
      case 'epub':
        final (title, chapters) = await _extractEpub(path);
        return FileReadResult(
          path: path,
          title: title.isNotEmpty ? title : titleFromFilename,
          chapters: chapters,
          type: SupportedFileType.epub,
        );
      default:
        return null;
    }
  }

  // ── PDF ─────────────────────────────────────────────────────────────────────
  // PDF has no paragraph structure — just positioned text. We read pdfrx's text
  // fragments WITH their coordinates, group them into visual lines, detect
  // running headers/footers across pages, then reflow each page's lines into
  // real paragraphs using vertical gaps / indentation / font-size (see
  // pdf_reflow.dart). Chapters come from the PDF's embedded outline (its real
  // table of contents) when it has one; only when there's no usable outline do
  // we fall back to one section per page ("Page N").
  Future<List<Chapter>> _extractPdf(String path) async {
    final doc = await PdfDocument.openFile(path);
    try {
      // Reflow every page into clean paragraphs (header/footer detection needs
      // all pages first).
      final pageLines = <List<PdfLine>>[];
      for (var i = 0; i < doc.pages.length; i++) {
        final text = await doc.pages[i].loadText();
        final frags = [
          for (final f in text.fragments)
            PdfFragment(
              f.text,
              f.bounds.left,
              f.bounds.top,
              f.bounds.right,
              f.bounds.bottom,
            ),
        ];
        pageLines.add(groupFragmentsIntoLines(frags));
      }
      final running = detectRunningHeaders(pageLines);
      final pageParagraphs = <List<String>>[
        for (final lines in pageLines) reflowLines(lines, runningHeaders: running),
      ];

      // TOC priority: (1) the PDF's embedded outline, (2) font-size headings in
      // the text (for books like this that have no bookmarks), (3) one section
      // per page as a last resort.
      final outline = await _loadOutlineSafely(doc);
      final chapters = _chaptersFromOutline(outline, pageParagraphs) ??
          _fromReflowChapters(chaptersByHeading(pageLines, runningHeaders: running)) ??
          _chaptersPerPage(pageParagraphs);

      if (chapters.isEmpty) {
        // No selectable text anywhere — almost always a scanned/image PDF.
        return [
          Chapter(title: 'No selectable text', paragraphs: const [
            'This PDF has no selectable text — it looks like scanned images. '
                'Read-aloud needs a text layer, so this file can’t be read aloud '
                'without an OCR step.',
          ]),
        ];
      }
      return chapters;
    } finally {
      doc.dispose();
    }
  }

  Future<List<PdfOutlineNode>> _loadOutlineSafely(PdfDocument doc) async {
    try {
      return await doc.loadOutline();
    } catch (_) {
      return const [];
    }
  }

  /// Depth-first flatten of the outline into (title, 0-based page) in reading
  /// order, skipping nodes without a title or destination.
  List<MapEntry<String, int>> _flattenOutline(
      List<PdfOutlineNode> nodes, int pageCount) {
    final out = <MapEntry<String, int>>[];
    void walk(List<PdfOutlineNode> ns) {
      for (final n in ns) {
        final dest = n.dest;
        final title = n.title.trim();
        if (dest != null && title.isNotEmpty) {
          out.add(MapEntry(title, (dest.pageNumber - 1).clamp(0, pageCount - 1)));
        }
        if (n.children.isNotEmpty) walk(n.children);
      }
    }

    walk(nodes);
    return out;
  }

  /// Build chapters from the embedded outline: one chapter per distinct start
  /// page (nested entries sharing a page collapse to the outermost title),
  /// gathering that page-range's paragraphs. Returns null when the outline is
  /// unusable — empty, or so dense (≈a bookmark per page) that it's no better
  /// than the page list — so the caller uses the per-page fallback.
  List<Chapter>? _chaptersFromOutline(
      List<PdfOutlineNode> outline, List<List<String>> pageParagraphs) {
    final pageCount = pageParagraphs.length;
    if (pageCount == 0) return null;
    final entries = _flattenOutline(outline, pageCount)
      ..sort((a, b) => a.value.compareTo(b.value));
    if (entries.isEmpty) return null;

    // Collapse entries that start on the same page (keep the first title).
    final dedup = <MapEntry<String, int>>[];
    for (final e in entries) {
      if (dedup.isEmpty || dedup.last.value != e.value) dedup.add(e);
    }
    if (dedup.length > (pageCount * 0.9).floor() && dedup.length > 5) {
      return null; // outline is basically a page list — not an improvement
    }

    final chapters = <Chapter>[];
    // Front matter before the first bookmark, if it carries text.
    final firstPage = dedup.first.value;
    if (firstPage > 0) {
      final para = <String>[
        for (var p = 0; p < firstPage; p++) ...pageParagraphs[p]
      ];
      if (para.isNotEmpty) chapters.add(Chapter(title: 'Beginning', paragraphs: para));
    }
    for (var k = 0; k < dedup.length; k++) {
      final start = dedup[k].value;
      final end = k + 1 < dedup.length ? dedup[k + 1].value : pageCount;
      final para = <String>[
        for (var p = start; p < end; p++) ...pageParagraphs[p]
      ];
      if (para.isEmpty) continue;
      chapters.add(Chapter(title: dedup[k].key, paragraphs: para));
    }
    return chapters.isEmpty ? null : chapters;
  }

  List<Chapter>? _fromReflowChapters(List<ReflowChapter>? cs) => cs == null
      ? null
      : [for (final c in cs) Chapter(title: c.title, paragraphs: c.paragraphs)];

  List<Chapter> _chaptersPerPage(List<List<String>> pageParagraphs) {
    final chapters = <Chapter>[];
    for (var i = 0; i < pageParagraphs.length; i++) {
      if (pageParagraphs[i].isEmpty) continue; // skip blank / image-only pages
      chapters.add(Chapter(title: 'Page ${i + 1}', paragraphs: pageParagraphs[i]));
    }
    return chapters;
  }

  // ── EPUB ────────────────────────────────────────────────────────────────────
  Future<(String, List<Chapter>)> _extractEpub(String path) async {
    final bytes = await File(path).readAsBytes();
    final book = await EpubReader.readBook(bytes);
    final title = book.Title ?? '';
    final chapters = <Chapter>[];

    void walk(EpubChapter ch) {
      final paragraphs =
          ch.HtmlContent != null ? _htmlToParagraphs(ch.HtmlContent!) : const <String>[];
      if (paragraphs.isNotEmpty) {
        final t = (ch.Title ?? '').trim();
        chapters.add(Chapter(
          title: t.isNotEmpty ? t : 'Chapter ${chapters.length + 1}',
          paragraphs: paragraphs,
        ));
      }
      for (final sub in ch.SubChapters ?? const <EpubChapter>[]) {
        walk(sub);
      }
    }

    for (final ch in book.Chapters ?? const <EpubChapter>[]) {
      walk(ch);
    }
    return (title, chapters);
  }

  /// Turn an HTML chapter body into paragraphs: insert breaks at block
  /// boundaries, strip remaining tags, decode entities, drop empties.
  List<String> _htmlToParagraphs(String html) {
    final withBreaks = html.replaceAll(
      RegExp(r'<\s*(br|/p|/div|/h[1-6]|/li|/blockquote)[^>]*>', caseSensitive: false),
      '\n\n',
    );
    final stripped = withBreaks.replaceAll(RegExp(r'<[^>]+>'), ' ');
    return _splitParagraphs(_decodeEntities(stripped));
  }

  /// Split on blank lines into trimmed, whitespace-normalised paragraphs.
  List<String> _splitParagraphs(String text) => text
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\s*\n\s*'), ' ').trim())
      .where((p) => p.isNotEmpty)
      .toList();

  String _decodeEntities(String s) => s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&rsquo;', "’")
      .replaceAll('&lsquo;', "‘")
      .replaceAll('&rdquo;', "”")
      .replaceAll('&ldquo;', "“")
      .replaceAll('&mdash;', "—")
      .replaceAll('&ndash;', "–")
      .replaceAll('&hellip;', "…");
}

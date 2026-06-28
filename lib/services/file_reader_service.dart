import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:epubx/epubx.dart';

import '../models/document.dart';

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
  // No reliable chapter structure in raw PDF text, so v1 is a single chapter
  // whose paragraphs come from every page (page chaptering is a later refinement).
  Future<List<Chapter>> _extractPdf(String path) async {
    final doc = await PdfDocument.openFile(path);
    final paragraphs = <String>[];
    for (var i = 0; i < doc.pages.length; i++) {
      final pageText = (await doc.pages[i].loadText()).fullText;
      paragraphs.addAll(_splitParagraphs(pageText));
    }
    return [Chapter(title: 'Full text', paragraphs: paragraphs)];
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

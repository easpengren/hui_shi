import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:epubx/epubx.dart';

enum SupportedFileType { txt, pdf, epub }

class FileReadResult {
  final String path;
  final String title;
  final String content;
  final SupportedFileType type;

  const FileReadResult({
    required this.path,
    required this.title,
    required this.content,
    required this.type,
  });
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
    return _readFromPath(picked.files.single.path!);
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
        final content = await File(path).readAsString();
        return FileReadResult(
          path: path,
          title: titleFromFilename,
          content: content,
          type: SupportedFileType.txt,
        );
      case 'pdf':
        final content = await _extractPdf(path);
        return FileReadResult(
          path: path,
          title: titleFromFilename,
          content: content,
          type: SupportedFileType.pdf,
        );
      case 'epub':
        final (title, content) = await _extractEpub(path);
        return FileReadResult(
          path: path,
          title: title.isNotEmpty ? title : titleFromFilename,
          content: content,
          type: SupportedFileType.epub,
        );
      default:
        return null;
    }
  }

  Future<String> _extractPdf(String path) async {
    final doc = await PdfDocument.openFile(path);
    final buffer = StringBuffer();
    for (var i = 1; i <= doc.pages.length; i++) {
      final page = doc.pages[i - 1];
      final pageText = await page.loadText();
      buffer.writeln(pageText.fullText);
    }
    return buffer.toString();
  }

  Future<(String, String)> _extractEpub(String path) async {
    final bytes = await File(path).readAsBytes();
    final book = await EpubReader.readBook(bytes);
    final title = book.Title ?? '';
    final buffer = StringBuffer();
    if (book.Chapters != null) {
      for (final chapter in book.Chapters!) {
        _appendChapter(chapter, buffer);
      }
    }
    return (title, buffer.toString());
  }

  void _appendChapter(EpubChapter chapter, StringBuffer buffer) {
    if (chapter.HtmlContent != null) {
      final text = chapter.HtmlContent!
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.isNotEmpty) buffer.writeln(text);
    }
    if (chapter.SubChapters != null) {
      for (final sub in chapter.SubChapters!) {
        _appendChapter(sub, buffer);
      }
    }
  }
}

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:epubx/epubx.dart';

enum SupportedFileType { txt, pdf, epub }

class FileReadResult {
  final String path;
  final String title;
  final String content;
  final SupportedFileType type;
  final bool hasMorePdfContent;
  final int? pdfNextPage;

  const FileReadResult({
    required this.path,
    required this.title,
    required this.content,
    required this.type,
    this.hasMorePdfContent = false,
    this.pdfNextPage,
  });
}

class PdfExtractResult {
  final String content;
  final bool truncated;
  final int? nextPage;

  const PdfExtractResult({
    required this.content,
    required this.truncated,
    this.nextPage,
  });
}

class FileReaderService {
  static const int _maxExtractedChars = 1500000;

  /// Show the system file picker and return the read result, or null if
  /// the user cancelled.
  Future<FileReadResult?> pickAndRead({
    void Function(String status)? onProgress,
  }) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'pdf', 'epub'],
    );
    if (picked == null || picked.files.single.path == null) return null;
    return _readFromPath(picked.files.single.path!, onProgress: onProgress);
  }

  /// Re-read a file that is already on-device (e.g. from the library).
  Future<FileReadResult?> readFromPath(
    String path, {
    void Function(String status)? onProgress,
  }) => _readFromPath(path, onProgress: onProgress);

  Future<FileReadResult?> _readFromPath(
    String path, {
    void Function(String status)? onProgress,
  }) async {
    debugPrint('[LuJi] _readFromPath: path=$path');
    final fileExists = File(path).existsSync();
    debugPrint('[LuJi] _readFromPath: fileExists=$fileExists');
    if (!fileExists) return null;

    final filename = path.split('/').last;
    final ext = filename.split('.').last.toLowerCase();
    final titleFromFilename = filename.replaceAll(RegExp(r'\.[^.]+$'), '');

    switch (ext) {
      case 'txt':
        onProgress?.call('Reading text file...');
        final content = await File(path).readAsString();
        return FileReadResult(
          path: path,
          title: titleFromFilename,
          content: content,
          type: SupportedFileType.txt,
        );
      case 'pdf':
        final result = await _extractPdf(path, onProgress: onProgress);
        return FileReadResult(
          path: path,
          title: titleFromFilename,
          content: result.content,
          type: SupportedFileType.pdf,
          hasMorePdfContent: result.truncated,
          pdfNextPage: result.nextPage,
        );
      case 'epub':
        onProgress?.call('Reading EPUB...');
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

  Future<PdfExtractResult> _extractPdf(
    String path, {
    void Function(String status)? onProgress,
  }) async {
    onProgress?.call('Opening PDF...');
    debugPrint('[LuJi] _extractPdf: opening $path');
    final doc = await PdfDocument.openFile(path);
    debugPrint('[LuJi] _extractPdf: opened, pageCount=${doc.pages.length}');
    final buffer = StringBuffer();
    final pageCount = doc.pages.length;
    var nextPage = 1;
    var truncated = false;
    for (var i = 1; i <= pageCount; i++) {
      if (i == 1 || i % 10 == 0 || i == pageCount) {
        onProgress?.call('Extracting PDF page $i / $pageCount...');
      }
      try {
        final page = doc.pages[i - 1];
        final pageText = await page.loadText();
        buffer.writeln(pageText.fullText);
      } catch (e) {
        debugPrint('[LuJi] _extractPdf: page $i error: $e');
        // Skip unreadable pages and continue extraction.
      }

      if (buffer.length >= _maxExtractedChars) {
        onProgress?.call('Large PDF detected. Loading first part for now...');
        truncated = true;
        nextPage = i + 1;
        break;
      }
    }
    final text = buffer.toString();
    final sliced = text.length <= _maxExtractedChars
        ? text
        : text.substring(0, _maxExtractedChars);
    debugPrint('[LuJi] _extractPdf: done. chars=${sliced.length}, truncated=$truncated, nextPage=$nextPage');
    return PdfExtractResult(
      content: sliced,
      truncated: truncated && nextPage <= pageCount,
      nextPage: truncated && nextPage <= pageCount ? nextPage : null,
    );
  }

  Future<String> continuePdfExtraction(
    String path,
    int startPage, {
    void Function(String status)? onProgress,
  }) async {
    final doc = await PdfDocument.openFile(path);
    final buffer = StringBuffer();
    final pageCount = doc.pages.length;

    for (var i = startPage; i <= pageCount; i++) {
      if (i == startPage || i % 10 == 0 || i == pageCount) {
        onProgress?.call('Continuing PDF extraction page $i / $pageCount...');
      }
      try {
        final page = doc.pages[i - 1];
        final pageText = await page.loadText();
        buffer.writeln(pageText.fullText);
      } catch (e) {
        debugPrint('[LuJi] continuePdf: page $i error: $e');
        // Skip unreadable pages and continue extraction.
      }
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

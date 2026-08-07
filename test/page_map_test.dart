import 'package:flutter_test/flutter_test.dart';
import 'package:lu_ji/models/document.dart';
import 'package:lu_ji/services/page_map.dart';

/// A page number is metadata, not a measurement — it exists only where the
/// source carried it. These pin that it is never invented, and that an anchor
/// survives the chunking that happens between extraction and playback.
void main() {
  group('normalizePageLabel', () {
    test('forgives the ways a page is written', () {
      for (final s in ['12', ' 12 ', 'p. 12', 'p12', 'Page 12', 'PAGE 12', 'pg 12']) {
        expect(normalizePageLabel(s), '12', reason: s);
      }
    });

    test('roman numerals fold to one case', () {
      expect(normalizePageLabel('XIV'), 'xiv');
      expect(normalizePageLabel('p. xiv'), 'xiv');
    });
  });

  group('inline markers (plain text and, via HTML, EPUB)', () {
    test('markers are removed and recorded', () {
      final (cleaned, anchors) = extractInlinePageMarkers([
        'First paragraph.',
        '[Pg 45] Second paragraph starts the page.',
        'Third paragraph.',
      ]);
      expect(cleaned[1], 'Second paragraph starts the page.');
      expect(anchors, {1: '45'});
    });

    test('a marker mid-paragraph still anchors the whole paragraph', () {
      // The page turned mid-sentence; the reader wants the sentence.
      final (cleaned, anchors) = extractInlinePageMarkers(
          ['a sentence broken [Pg 46] across the turn']);
      expect(cleaned.single, 'a sentence broken across the turn');
      expect(anchors, {0: '46'});
    });

    test('roman and Page spellings', () {
      final (_, anchors) =
          extractInlinePageMarkers(['[Page xiv] Preface.', '[pg. 3] Body.']);
      expect(anchors, {0: 'xiv', 1: '3'});
    });

    test('text without markers is untouched', () {
      const paragraphs = ['Nothing here.', 'Nor [sic] here.'];
      final (cleaned, anchors) = extractInlinePageMarkers(paragraphs);
      expect(cleaned, paragraphs);
      expect(anchors, isEmpty);
    });
  });

  group('EPUB page-break anchors', () {
    test('epub:type pagebreak with a title', () {
      expect(
        markPageBreaksInHtml(
            '<p>Before<span epub:type="pagebreak" id="page213" '
            'title="213"/>After</p>'),
        contains('[Pg 213]'),
      );
    });

    test('role=doc-pagebreak with aria-label', () {
      expect(
        markPageBreaksInHtml('<span role="doc-pagebreak" aria-label="99"></span>'),
        contains('[Pg 99]'),
      );
    });

    test('falls back to the id when there is no label', () {
      expect(markPageBreaksInHtml('<a epub:type="pagebreak" id="page_77"/>'),
          contains('[Pg 77]'));
    });

    test('ordinary markup is untouched', () {
      const html = '<p>A paragraph with <em>emphasis</em> in it.</p>';
      expect(markPageBreaksInHtml(html), html);
    });
  });

  group('fillPageLabels', () {
    test('carries the sequence across an unnumbered page', () {
      // Chapter openings usually print no folio but still count.
      expect(fillPageLabels(['12', null, null, '15']), ['12', '13', '14', '15']);
    });

    test('a printed number always wins over the assumption', () {
      expect(fillPageLabels(['12', null, '40']), ['12', '13', '40']);
    });

    test('roman numerals are not incremented', () {
      // Guessing "xiv" + 1 is more likely to be wrong than useful.
      expect(fillPageLabels(['xii', null]), ['xii', null]);
    });

    test('leading pages with no number stay unknown', () {
      expect(fillPageLabels([null, null, '1']), [null, null, '1']);
    });
  });

  group('buildChunkedDocument', () {
    Chapter ch(String title, List<String> paragraphs) =>
        Chapter(title: title, paragraphs: paragraphs);

    test('a book with no page data reports none', () {
      final doc = buildChunkedDocument(chapters: [
        ch('One', ['First paragraph.', 'Second paragraph.']),
      ]);
      expect(doc.hasPages, isFalse);
      expect(doc.chunkForPage('1'), isNull,
          reason: 'a page must never be invented');
      expect(doc.chunks.length, 2);
    });

    test('an anchor lands on the right chunk', () {
      final doc = buildChunkedDocument(
        chapters: [ch('One', ['Para zero.', 'Para one.', 'Para two.'])],
        pageStarts: {1: '13'},
      );
      expect(doc.hasPages, isTrue);
      expect(doc.chunkForPage('13'), 1);
      expect(doc.chunks[doc.chunkForPage('13')!], 'Para one.');
    });

    test('anchors survive a paragraph splitting into several chunks', () {
      // THE REASON anchors are recorded against paragraphs, not chunks: a long
      // paragraph becomes many chunks and would shift every later anchor.
      final long = 'This is a sentence. ' * 200; // well over maxLen
      final doc = buildChunkedDocument(
        chapters: [ch('One', ['Short.', long, 'After the long one.'])],
        pageStarts: {0: '1', 2: '2'},
      );
      expect(doc.chunks.length, greaterThan(3));
      expect(doc.chunkForPage('1'), 0);
      expect(doc.chunks[doc.chunkForPage('2')!], 'After the long one.');
    });

    test('anchors survive dropped boilerplate', () {
      final doc = buildChunkedDocument(
        chapters: [
          ch('Front', ['All rights reserved.', 'ISBN 978-0-00-000000-0']),
          ch('One', ['The real beginning.', 'And onward.']),
        ],
        pageStarts: {2: '1', 3: '2'},
      );
      expect(doc.chunks, ['The real beginning.', 'And onward.']);
      expect(doc.chunkForPage('1'), 0);
      expect(doc.chunkForPage('2'), 1);
    });

    test('lookup is forgiving about how a page is typed', () {
      final doc = buildChunkedDocument(
        chapters: [ch('One', ['a.', 'b.'])],
        pageStarts: {1: '213'},
      );
      for (final typed in ['213', 'p. 213', 'Page 213', ' 213 ']) {
        expect(doc.chunkForPage(typed), 1, reason: typed);
      }
    });

    test('the page in force is reported for any chunk', () {
      final doc = buildChunkedDocument(
        chapters: [ch('One', ['a.', 'b.', 'c.'])],
        pageStarts: {1: '7'},
      );
      expect(doc.pageAt(0), isNull, reason: 'before the first anchor');
      expect(doc.pageAt(1), '7');
      expect(doc.pageAt(2), '7', reason: 'the page continues until the next');
    });

    test('chapter starts still line up', () {
      final doc = buildChunkedDocument(chapters: [
        ch('One', ['a.', 'b.']),
        ch('Two', ['c.']),
      ]);
      expect(doc.chapterChunkStarts, [0, 2]);
    });

    test('the Gutenberg wrapper is excluded and does not shift anchors', () {
      final doc = buildChunkedDocument(
        chapters: [
          ch('Book', [
            'The Project Gutenberg eBook of Something',
            '*** START OF THE PROJECT GUTENBERG EBOOK X ***',
            'The real first paragraph.',
            '*** END OF THE PROJECT GUTENBERG EBOOK X ***',
            'Most people start at our website.',
          ]),
        ],
        pageStarts: {2: '1'},
      );
      expect(doc.chunks, ['The real first paragraph.']);
      expect(doc.chunkForPage('1'), 0);
    });

    test('an empty document is safe', () {
      final doc = buildChunkedDocument(chapters: const []);
      expect(doc.chunks, isEmpty);
      expect(doc.hasPages, isFalse);
      expect(doc.pageAt(0), isNull);
    });
  });
}

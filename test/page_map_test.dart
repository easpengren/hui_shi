import 'package:flutter_test/flutter_test.dart';
import 'package:lu_ji/services/chunking_service.dart';
import 'package:lu_ji/services/front_matter.dart';
import 'package:lu_ji/services/page_map.dart';
import 'package:lu_ji/services/text_cleaner.dart';

/// A page number is metadata, not a measurement — it exists only where the
/// source carried it. These pin that it is never invented, and that an anchor
/// survives cleaning, chunking, boilerplate filtering, and the re-chunk that
/// happens when another batch of a large PDF loads.
void main() {
  group('normalizePageLabel', () {
    test('forgives the ways a page is written', () {
      for (final s in ['12', ' 12 ', 'p. 12', 'p12', 'Page 12', 'pg 12']) {
        expect(normalizePageLabel(s), '12', reason: s);
      }
    });

    test('roman numerals fold to one case', () {
      expect(normalizePageLabel('XIV'), 'xiv');
      expect(normalizePageLabel('p. xiv'), 'xiv');
    });
  });

  group('printedPageNumberFromText', () {
    test('a folio at the foot of the page', () {
      expect(
        printedPageNumberFromText('CHAPTER ONE\nIt was a bright cold day.\n213'),
        '213',
      );
    });

    test('the foot wins over a numeric running head', () {
      expect(
        printedPageNumberFromText('12\nBody text here.\nMore body.\n213'),
        '213',
      );
    });

    test('roman folios in front matter', () {
      expect(printedPageNumberFromText('Preface\nSome text.\nxiv'), 'xiv');
    });

    test('strips a Page or p. prefix', () {
      expect(printedPageNumberFromText('Body.\nPage 45'), '45');
      expect(printedPageNumberFromText('Body.\np. 45'), '45');
    });

    test('a page with no folio returns null', () {
      // Chapter openers usually omit it; fillPageLabels carries the sequence.
      expect(
        printedPageNumberFromText('CHAPTER ONE\nIt was a bright cold day.'),
        isNull,
      );
    });

    test('a number in the body is not a folio', () {
      // Only the top and bottom bands are considered.
      expect(
        printedPageNumberFromText(
            'Heading\nThere were 213 of them.\n42 more arrived.\nEnd of text.'),
        isNull,
      );
    });
  });

  group('fillPageLabels', () {
    test('carries the sequence across an unnumbered page', () {
      expect(fillPageLabels(['12', null, null, '15']), ['12', '13', '14', '15']);
    });

    test('a printed number wins over the assumption', () {
      expect(fillPageLabels(['12', null, '40']), ['12', '13', '40']);
    });

    test('roman numerals are not incremented', () {
      expect(fillPageLabels(['xii', null]), ['xii', null]);
    });

    test('leading pages with no number stay unknown', () {
      expect(fillPageLabels([null, null, '1']), [null, null, '1']);
    });
  });

  group('EPUB page-break anchors', () {
    test('epub:type pagebreak with a title', () {
      expect(
        markPageBreaksInHtml(
            '<p>Before<span epub:type="pagebreak" id="page213" title="213"/>'
            'After</p>'),
        contains('[Pg 213]'),
      );
    });

    test('role=doc-pagebreak with aria-label', () {
      expect(
        markPageBreaksInHtml('<span role="doc-pagebreak" aria-label="99"></span>'),
        contains('[Pg 99]'),
      );
    });

    test('falls back to the id', () {
      expect(markPageBreaksInHtml('<a epub:type="pagebreak" id="page_77"/>'),
          contains('[Pg 77]'));
    });

    test('ordinary markup is untouched', () {
      const html = '<p>A paragraph with <em>emphasis</em> in it.</p>';
      expect(markPageBreaksInHtml(html), html);
    });
  });

  group('extractPageAnchors', () {
    test('a marker on its own anchors what follows and is not spoken', () {
      final paged = extractPageAnchors(
          ['Before the turn.', '[Pg 213]', 'After the turn.']);
      expect(paged.chunks, ['Before the turn.', 'After the turn.'],
          reason: 'a marker must never reach a speech engine');
      expect(paged.chunkForPage('213'), 1);
      expect(paged.pageAt(1), '213');
    });

    test('an embedded marker is stripped and anchors its own chunk', () {
      final paged = extractPageAnchors(['a sentence [Pg 46] broken across it']);
      expect(paged.chunks.single, 'a sentence broken across it');
      expect(paged.chunkForPage('46'), 0);
    });

    test('the page continues until the next marker', () {
      final paged = extractPageAnchors(
          ['[Pg 1]', 'one.', 'two.', '[Pg 2]', 'three.']);
      expect(paged.pageAt(0), '1');
      expect(paged.pageAt(1), '1');
      expect(paged.pageAt(2), '2');
    });

    test('text before the first marker has no page', () {
      final paged = extractPageAnchors(['front.', '[Pg 1]', 'body.']);
      expect(paged.pageAt(0), isNull);
    });

    test('a book with no markers reports no pages', () {
      final paged = extractPageAnchors(['one.', 'two.']);
      expect(paged.hasPages, isFalse);
      expect(paged.chunkForPage('1'), isNull,
          reason: 'a page must never be invented');
    });

    test('lookup is forgiving about how a page is typed', () {
      final paged = extractPageAnchors(['[Pg 213]', 'body.']);
      for (final typed in ['213', 'p. 213', 'Page 213', ' 213 ']) {
        expect(paged.chunkForPage(typed), 0, reason: typed);
      }
    });

    test('roman folios', () {
      final paged = extractPageAnchors(['[Pg xiv]', 'preface text.']);
      expect(paged.chunkForPage('XIV'), 0);
    });

    test('an empty document is safe', () {
      final paged = extractPageAnchors(const []);
      expect(paged.chunks, isEmpty);
      expect(paged.hasPages, isFalse);
      expect(paged.pageAt(0), isNull);
    });
  });

  group('anchors survive the whole pipeline', () {
    // How a PDF actually arrives: marker line, then that page's text.
    String pdfLike() => [
          '[Pg 1]',
          'The first page of the book begins here.',
          '[Pg 2]',
          'The second page continues the thought. It has two sentences.',
          '[Pg 3]',
          'The third page ends it.',
        ].join('\n');

    test('cleaning, chunking and boilerplate filtering keep the anchors', () {
      final paged = extractPageAnchors(
          dropBoilerplate(chunkText(cleanText(pdfLike()))));
      expect(paged.hasPages, isTrue);
      expect(paged.pageLabels, ['1', '2', '3']);
      expect(paged.chunks[paged.chunkForPage('3')!],
          'The third page ends it.');
      for (final c in paged.chunks) {
        expect(c, isNot(contains('[Pg')), reason: 'marker leaked into speech');
      }
    });

    test('re-chunking after a batch loads keeps them consistent', () {
      // The large-PDF path re-chunks the whole accumulated text each time.
      final more = '${pdfLike()}\n[Pg 4]\nA fourth page arrives later.';
      final paged =
          extractPageAnchors(dropBoilerplate(chunkText(cleanText(more))));
      expect(paged.pageLabels, ['1', '2', '3', '4']);
      expect(paged.chunks[paged.chunkForPage('4')!],
          'A fourth page arrives later.');
    });

    test('a page number is not read aloud', () {
      final paged = extractPageAnchors(
          dropBoilerplate(chunkText(cleanText(pdfLike()))));
      expect(sanitizeForTts(paged.chunks.first), isNot(contains('Pg')));
    });
  });
}

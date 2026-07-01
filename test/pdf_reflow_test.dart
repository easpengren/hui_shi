import 'package:flutter_test/flutter_test.dart';
import 'package:lu_ji/services/pdf_reflow.dart';

// Helper: a full-width body line at a given vertical band (y-up, top >= bottom).
PdfLine line(String text, double top, {double left = 100, double right = 400}) =>
    PdfLine(text, left, right, top, top - 10);

void main() {
  group('groupFragmentsIntoLines', () {
    test('groups fragments on the same row and orders left-to-right', () {
      final frags = [
        const PdfFragment('world', 145, 700, 190, 690),
        const PdfFragment('Hello', 100, 700, 140, 690),
        const PdfFragment('Next', 100, 680, 140, 670),
      ];
      final lines = groupFragmentsIntoLines(frags);
      expect(lines.length, 2);
      expect(lines[0].text, 'Hello world');
      expect(lines[1].text, 'Next');
    });
  });

  group('reflowLines', () {
    test('joins wrapped lines and splits at a vertical gap', () {
      final lines = [
        line('First paragraph line one', 700),
        line('continues here and ends.', 688), // small gap → same para
        line('Second paragraph starts now', 664), // big gap → new para
        line('and finishes here.', 652),
      ];
      final paras = reflowLines(lines);
      expect(paras.length, 2);
      expect(paras[0], 'First paragraph line one continues here and ends.');
      expect(paras[1], 'Second paragraph starts now and finishes here.');
    });

    test('starts a new paragraph on first-line indentation', () {
      final lines = [
        line('A paragraph that wraps over', 700),
        line('to a second line of text.', 688),
        line('Indented new paragraph here.', 676, left: 120), // indent
      ];
      final paras = reflowLines(lines);
      expect(paras.length, 2);
      expect(paras[1], 'Indented new paragraph here.');
    });

    test('de-hyphenates a word broken across a line', () {
      final lines = [
        line('campaigns draw on recent break-', 700),
        line('throughs in new media today.', 688),
      ];
      final paras = reflowLines(lines);
      expect(paras.single, contains('breakthroughs'));
      expect(paras.single, isNot(contains('break-')));
    });

    test('treats a larger-font line as a heading on its own', () {
      final lines = [
        PdfLine('Chapter One', 100, 250, 700, 684), // height 16
        line('Body text follows the heading here.', 678),
        line('And it continues for another line.', 666),
        line('Finally ending the body paragraph.', 654),
      ];
      final paras = reflowLines(lines);
      expect(paras.first, 'Chapter One');
      expect(paras[1], startsWith('Body text follows'));
    });

    test('drops page numbers and running headers', () {
      final lines = [
        line('CAMPAIGNING TO ENGAGE AND WIN', 700), // running header
        line('Real body text that should survive.', 680),
        line('42', 100), // page number footer
      ];
      final paras =
          reflowLines(lines, runningHeaders: {'CAMPAIGNING TO ENGAGE AND WIN'});
      expect(paras.length, 1);
      expect(paras.single, 'Real body text that should survive.');
    });
  });

  group('detectRunningHeaders', () {
    test('finds a header repeated across many pages', () {
      final pages = [
        for (var i = 0; i < 10; i++)
          [line('RUNNING HEADER', 700), line('Unique body $i.', 680)],
      ];
      expect(detectRunningHeaders(pages), contains('RUNNING HEADER'));
    });

    test('returns empty for short documents', () {
      expect(detectRunningHeaders([[], []]), isEmpty);
    });

    test('catches an export footer whose page number is embedded mid-line', () {
      // Real case (Machiavelli, The Prince): an InDesign export footer of the
      // form "<file>.indd <page>   <timestamp>" — the page number sits in the
      // MIDDLE, so edge-only stripping left every page's footer unique and it
      // was never detected. Normalizing all embedded page numbers fixes it.
      const words = 'alpha beta gamma delta epsilon zeta eta theta iota kappa '
          'lambda mu';
      final wordList = words.split(' ');
      final pages = [
        for (var i = 0; i < wordList.length; i++)
          [
            // Genuinely unique body text per page (not just a differing number).
            line('The chapter discusses ${wordList[i]} in careful detail.', 700),
            line('780141395876_ThePrince_PRE.indd ${20 + i}   21/05/15 3:00 PM', 60),
          ],
      ];
      final running = detectRunningHeaders(pages);
      // The footer is detected...
      expect(running, isNotEmpty);
      // ...and dropped from the reflowed body of a page, while real body stays.
      final body = reflowLines(pages[0], runningHeaders: running);
      expect(body.join(' '), isNot(contains('ThePrince_PRE.indd')));
      expect(body.join(' '), isNot(contains('3:00 PM')));
      expect(body.join(' '), contains('alpha'));
    });
  });

  group('isPageNumberLine', () {
    test('matches numbers/romans/labels but not words', () {
      expect(isPageNumberLine('42'), isTrue);
      expect(isPageNumberLine('ii'), isTrue);
      expect(isPageNumberLine('Page 7'), isTrue);
      expect(isPageNumberLine('I'), isFalse);
      expect(isPageNumberLine('Introduction'), isFalse);
    });
  });

  group('chaptersByHeading', () {
    // A tall line (bigger font) reads as a chapter heading; body lines are h10.
    PdfLine head(String t, double top) => PdfLine(t, 100, 400, top, top - 20);

    test('splits into chapters at font-size headings; drops the title text', () {
      final pages = [
        [head('Chapter One', 720), line('First body of one.', 690), line('More one.', 675)],
        [line('Continued body of chapter one.', 720)],
        [head('Chapter Two', 720), line('Body of two.', 690)],
        [line('Continued body of chapter two.', 720)],
      ];
      final chs = chaptersByHeading(pages);
      expect(chs, isNotNull);
      expect(chs!.map((c) => c.title).toList(), ['Chapter One', 'Chapter Two']);
      final one = chs[0].paragraphs.join(' ');
      expect(one, contains('First body of one'));
      expect(one, contains('Continued body of chapter one'));
      expect(one, isNot(contains('Chapter One'))); // title not duplicated in body
      expect(chs[1].paragraphs.join(' '), contains('Body of two'));
    });

    test('returns null when there is no heading structure', () {
      final pages = [
        for (var i = 0; i < 6; i++) [line('Plain body line about topic $i.', 720)]
      ];
      expect(chaptersByHeading(pages), isNull);
    });
  });
}

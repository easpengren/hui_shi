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
}

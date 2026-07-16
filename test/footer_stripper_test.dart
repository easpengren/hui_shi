import 'package:flutter_test/flutter_test.dart';
import 'package:lu_ji/utils/footer_stripper.dart';

void main() {
  group('stripRepeatedHeadersFooters', () {
    String page(int n, String body) =>
        'The Art of War\n$body\n$n';

    test('drops a running header + numeric footer that recur across pages', () {
      final pages = [
        for (var n = 1; n <= 6; n++) page(n, 'Body sentence for page $n.'),
      ];
      final out = stripRepeatedHeadersFooters(pages);
      for (var i = 0; i < out.length; i++) {
        expect(out[i], isNot(contains('The Art of War')));
        // The footer page number (a lone "1".."6") is gone...
        expect(out[i].trim(), 'Body sentence for page ${i + 1}.');
      }
    });

    test('keeps body text even when it contains numbers', () {
      final pages = [
        for (var n = 1; n <= 5; n++)
          'Running Header\nIn 1994 the count was 300 units.\n$n',
      ];
      final out = stripRepeatedHeadersFooters(pages);
      for (final p in out) {
        expect(p, contains('In 1994 the count was 300 units.'));
        expect(p, isNot(contains('Running Header')));
      }
    });

    test('drops "Page N of M" style footers', () {
      final pages = [
        for (var n = 1; n <= 8; n++) 'Chapter One\nReal content $n.\nPage $n of 8',
      ];
      final out = stripRepeatedHeadersFooters(pages);
      for (final p in out) {
        expect(p, isNot(contains('Page')));
        expect(p, isNot(contains('Chapter One')));
        expect(p, contains('Real content'));
      }
    });

    test('leaves short documents untouched (too few pages to tell)', () {
      final pages = ['Header\nBody one\n1', 'Header\nBody two\n2'];
      expect(stripRepeatedHeadersFooters(pages), pages);
    });

    test('does not drop a non-repeating band line', () {
      final pages = [
        'Unique Title Page\nintro\n1',
        'Common Footer\nchapter body two\n2',
        'Common Footer\nchapter body three\n3',
        'Common Footer\nchapter body four\n4',
      ];
      final out = stripRepeatedHeadersFooters(pages);
      // The one-off first-page title survives; the recurring footer is gone.
      expect(out[0], contains('Unique Title Page'));
      for (final p in out) {
        expect(p, isNot(contains('Common Footer')));
      }
    });
  });
}

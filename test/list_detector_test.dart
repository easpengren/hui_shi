import 'package:flutter_test/flutter_test.dart';
import 'package:lu_ji/services/chunking_service.dart';
import 'package:lu_ji/services/list_detector.dart';
import 'package:lu_ji/services/text_cleaner.dart';

/// A list item is a unit of speech — own chunk, own highlight, own pause.
///
/// The false-positive guards matter more than the detection: a detector that
/// shreds "He was born in 1990. The war ended in 1991." damages ordinary prose
/// everywhere to fix lists that appear rarely.
void main() {
  group('splitListItems finds lists', () {
    test('numbered, period', () {
      expect(splitListItems('1. The first item 2. The second item'),
          ['1. The first item', '2. The second item']);
    });

    test('numbered, paren and both', () {
      expect(splitListItems('1) First thing 2) Second thing'),
          ['1) First thing', '2) Second thing']);
      expect(splitListItems('1.) First thing 2.) Second thing'),
          ['1.) First thing', '2.) Second thing']);
    });

    test('alphabetical', () {
      expect(splitListItems('a. The first item b. The second item'),
          ['a. The first item', 'b. The second item']);
    });

    test('bulleted, with and without an inner number', () {
      expect(splitListItems('• 9. The first item • 10. The second item'),
          ['• 9. The first item', '• 10. The second item']);
      expect(splitListItems('⁃9. The first item ⁃10. The second item'),
          ['⁃9. The first item', '⁃10. The second item']);
    });

    test('three or more items', () {
      expect(
        splitListItems('a. First item b. Second item c. Third item'),
        ['a. First item', 'b. Second item', 'c. Third item'],
      );
    });
  });

  group('splitListItems refuses ordinary prose', () {
    test('years in consecutive sentences are not a list', () {
      // The motivating false positive: 1990 and 1991 are consecutive values
      // with prose between them.
      const s = 'He was born in 1990. The war ended in 1991. Peace came.';
      expect(splitListItems(s), [s]);
    });

    test('scores in consecutive sentences are not a list', () {
      const s = 'He scored 5. The crowd cheered. She scored 6. It ended.';
      expect(splitListItems(s), [s]);
    });

    test('initials are not a list', () {
      const s = 'The theorem is due to George E. P. Box, who was right.';
      expect(splitListItems(s), [s]);
    });

    test('consecutive initials are not a list', () {
      // A and B *are* consecutive; nothing sits between them, so it is a name.
      const s = 'I met John A. B. Smith yesterday at the party.';
      expect(splitListItems(s), [s]);
    });

    test('a run must start at the beginning', () {
      const s = 'Follow the steps: 1. Do this 2. Do that';
      expect(splitListItems(s), [s],
          reason: 'a mid-sentence marker run is not trusted');
    });

    test('non-consecutive values are not a list', () {
      const s = '1. The first item 5. Another item';
      expect(splitListItems(s), [s]);
    });

    test('plain prose is untouched', () {
      const s = 'All models are wrong. Some are useful. That is it.';
      expect(splitListItems(s), [s]);
    });
  });

  group('sentence splitting inside list items', () {
    test('the marker is never its own sentence', () {
      for (final item in splitSentences('1. The first item. 2. Second one.')) {
        expect(item, isNot(RegExp(r'^\d+[.)]+$')),
            reason: 'a bare marker chunk would be read as punctuation');
      }
    });

    test('an item keeps its marker', () {
      expect(splitSentences('1. The first item. 2. The second item.'),
          ['1. The first item.', '2. The second item.']);
    });
  });

  group('lists in real documents (one item per line)', () {
    test('list lines become separate paragraphs', () {
      final out = cleanText('Intro line\n\n1. First item\n2. Second item');
      expect(out.split('\n\n'),
          ['Intro line', '1. First item', '2. Second item']);
    });

    test('dash and asterisk bullets count at line start', () {
      expect(cleanText('- First item\n- Second item').split('\n\n'),
          ['- First item', '- Second item']);
    });

    test('a wrapped list item keeps its continuation', () {
      final out = cleanText('1. First item that\n   wraps over a line\n'
          '2. Second item');
      expect(out.split('\n\n'),
          ['1. First item that wraps over a line', '2. Second item']);
    });

    test('a mid-sentence dash does not start a block', () {
      // Only a line *opening* with a dash is a bullet.
      expect(cleanText('a quote\n— Eric Aspengren').split('\n\n').length, 2);
      expect(cleanText('one thing\nand — crucially — another').split('\n\n'),
          ['one thing and — crucially — another']);
    });

    test('each list item chunks separately', () {
      final chunks =
          chunkText(cleanText('1. First item\n2. Second item'), maxLen: 20);
      expect(chunks, ['1. First item', '2. Second item']);
    });
  });

  group('startsWithListMarker', () {
    test('accepts real markers', () {
      for (final line in ['1. Item', '2) Item', 'a. Item', '• Item',
        '- Item', '* Item', '⁃ Item', '10.) Item']) {
        expect(startsWithListMarker(line), isTrue, reason: line);
      }
    });

    test('rejects prose', () {
      for (final line in [
        'The first item',
        '1990 was the year',
        'and — crucially — another',
        'George E. P. Box said so',
      ]) {
        expect(startsWithListMarker(line), isFalse, reason: line);
      }
    });
  });
}

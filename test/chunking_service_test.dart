import 'package:flutter_test/flutter_test.dart';
import 'package:lu_ji/services/chunking_service.dart';
import 'package:lu_ji/services/text_cleaner.dart';

/// These pin two compounding defects that made the reader stutter mid-name:
///
///  1. `cleanText` collapsed every run of whitespace, so no blank lines
///     survived and `chunkText`'s paragraph branch was unreachable — every
///     document arrived as one paragraph.
///  2. `_splitBySentence` then cut on any `[.!?]` followed by a space, so
///     abbreviations and initials became chunk boundaries. Because a chunk
///     boundary is also a highlight boundary and an audible pause, "George
///     E. P. Box" was read as three fragments.
void main() {
  group('cleanText preserves structure', () {
    test('blank lines survive as paragraph breaks', () {
      final out = cleanText('First para.\n\nSecond para.');
      expect(out, 'First para.\n\nSecond para.');
      expect(out.split(RegExp(r'\n\s*\n')).length, 2);
    });

    test('soft wraps inside a paragraph are flattened', () {
      // A hard-wrapped source file must not become a pause per line.
      expect(
        cleanText('a line\nwrapped by width\n\nnext para'),
        'a line wrapped by width\n\nnext para',
      );
    });

    test('an indented wrapped line does not leave a double space', () {
      // The indent and the newline would each contribute a space.
      expect(cleanText('when they\n    diverge.'), 'when they diverge.');
    });

    test('runs of blank lines collapse to a single break', () {
      expect(cleanText('one\n\n\n\n\ntwo'), 'one\n\ntwo');
    });

    test('markup is still stripped', () {
      expect(cleanText('# Head\n\n**bold** [text](http://x) <b>tag</b>'),
          contains('Head'));
      expect(cleanText('# Head\n\n**bold**'), isNot(contains('#')));
      expect(cleanText('a <b>c</b>'), isNot(contains('<b>')));
    });

    test('CRLF sources behave the same as LF', () {
      expect(cleanText('one\r\n\r\ntwo'), 'one\n\ntwo');
    });

    test('sanitizeForTts still flattens to one line', () {
      // The engine gets a single chunk; the boundary supplies the pause.
      expect(sanitizeForTts('One thing.\n\nTwo things.'),
          'One thing. Two things.');
    });
  });

  group('splitSentences does not break mid-name', () {
    test('initials stay with the name', () {
      // THE REGRESSION, in its original form.
      expect(
        splitSentences('It is due to George E. P. Box. He was right.'),
        ['It is due to George E. P. Box.', 'He was right.'],
      );
    });

    test('dotted acronyms stay intact', () {
      expect(
        splitSentences('He joined the U.S. Census Bureau in May.'),
        ['He joined the U.S. Census Bureau in May.'],
      );
      expect(
        splitSentences('Use it, e.g. here. Then stop.'),
        ['Use it, e.g. here.', 'Then stop.'],
      );
    });

    test('titles stay with the surname', () {
      expect(splitSentences('Dr. Box spoke. Mr. Smith did not.'),
          ['Dr. Box spoke.', 'Mr. Smith did not.']);
    });

    test('reference abbreviations do not split', () {
      expect(
        splitSentences('See vol. 3, at No. 5, for the reply.'),
        ['See vol. 3, at No. 5, for the reply.'],
      );
    });

    test('ordinary sentences still split', () {
      expect(
        splitSentences('All models are wrong. Some are useful.'),
        ['All models are wrong.', 'Some are useful.'],
      );
      expect(splitSentences('Is it? Yes! It is.').length, 3);
    });

    test('a lower-case continuation is not a sentence end', () {
      expect(splitSentences('"Stop!" he said.'), ['"Stop!" he said.']);
    });

    test('ellipsis does not fragment a thought', () {
      expect(splitSentences('He paused... then went on.').length, 1);
    });

    test('closing quotes stay with their sentence', () {
      expect(
        splitSentences('He said "no." She left.'),
        ['He said "no."', 'She left.'],
      );
    });

    test('no text is lost or duplicated', () {
      const source =
          'Dr. Box, of the U.S. Census Bureau, wrote it. George E. P. Box, '
          'that is. See vol. 3. It holds.';
      final joined = splitSentences(source).join(' ');
      expect(joined, source);
    });

    test('empty and terminator-free input are safe', () {
      expect(splitSentences(''), isEmpty);
      expect(splitSentences('no terminator here'), ['no terminator here']);
    });
  });

  group('chunkText', () {
    test('chunks on paragraphs once cleaning preserves them', () {
      final chunks = chunkText(cleanText('One.\n\nTwo.\n\nThree.'), maxLen: 5);
      expect(chunks, ['One.', 'Two.', 'Three.']);
    });

    test('paragraphs are never packed together, whatever maxLen allows', () {
      // Packing cost a pause: sanitizeForTts flattens the blank line between
      // two joined paragraphs to a space, so the break became inaudible. One
      // paragraph per chunk makes it an utterance boundary instead.
      final chunks =
          chunkText(cleanText('One.\n\nTwo.\n\nThree.'), maxLen: 10000);
      expect(chunks, ['One.', 'Two.', 'Three.']);
      for (final c in chunks) {
        expect(c, isNot(contains('\n')), reason: 'chunk spans a paragraph');
      }
    });

    test('a chunk is never larger than maxLen', () {
      final long = 'This is a sentence. ' * 60;
      for (final c in chunkText(long, maxLen: 100)) {
        expect(c.length, lessThanOrEqualTo(100));
      }
    });

    test('a heading is not glued to the paragraph below it', () {
      final chunks = chunkText(cleanText('Doctrine\n\nThe body follows.'),
          maxLen: 20);
      expect(chunks.first, 'Doctrine');
    });

    test('over-long paragraphs fall back to sentence splitting', () {
      final long = 'This is a sentence. ' * 40; // ~800 chars, one paragraph
      final chunks = chunkText(long, maxLen: 100);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(100));
      }
    });

    test('no chunk ends on an initial or abbreviation', () {
      const source =
          'The theorem is named for George E. P. Box, who worked at the U.S. '
          'Census Bureau. Dr. Box put it plainly, e.g. in vol. 3 of his '
          'collected papers, at No. 5.';
      for (final c in chunkText(cleanText(source), maxLen: 60)) {
        expect(RegExp(r'\b[A-Z]\.$').hasMatch(c), isFalse,
            reason: 'chunk ends on an initial: "$c"');
        expect(RegExp(r'\b(Dr|Mr|Mrs|vol|No|U\.S)\.$').hasMatch(c), isFalse,
            reason: 'chunk ends on an abbreviation: "$c"');
      }
    });

    test('all source text survives chunking', () {
      const source = 'First para here.\n\nSecond para, with Dr. Box in it.';
      final rejoined = chunkText(cleanText(source)).join('\n\n');
      expect(rejoined, cleanText(source));
    });
  });

  group('rescaleChunkIndex', () {
    test('an unchanged chunk count keeps the exact position', () {
      expect(rescaleChunkIndex(index: 12, oldTotal: 40, newTotal: 40), 12);
    });

    test('a finer chunking keeps the same place in the book', () {
      // The old packing produced 4 chunks for a document that now makes 40.
      // Chunk 2 of 4 is the same *place* as chunk 20 of 40.
      expect(rescaleChunkIndex(index: 2, oldTotal: 4, newTotal: 40), 20);
    });

    test('a coarser chunking also maps back', () {
      expect(rescaleChunkIndex(index: 20, oldTotal: 40, newTotal: 4), 2);
    });

    test('a first-time open has no previous total', () {
      expect(rescaleChunkIndex(index: 0, oldTotal: 0, newTotal: 40), 0);
      expect(rescaleChunkIndex(index: 7, oldTotal: 0, newTotal: 40), 7);
    });

    test('never points past the end', () {
      expect(rescaleChunkIndex(index: 39, oldTotal: 40, newTotal: 4), 3);
      expect(rescaleChunkIndex(index: 900, oldTotal: 0, newTotal: 4), 3);
    });

    test('an empty document is position zero', () {
      expect(rescaleChunkIndex(index: 5, oldTotal: 40, newTotal: 0), 0);
    });
  });
}

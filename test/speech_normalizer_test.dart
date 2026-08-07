import 'package:flutter_test/flutter_test.dart';
import 'package:lu_ji/services/speech_normalizer.dart';
import 'package:lu_ji/services/text_cleaner.dart';

/// Normalisation runs only on the way into a speech engine. The load-bearing
/// property is that the *displayed* text never changes — that is what makes it
/// safe to rewrite "e.g." as "for example".
void main() {
  group('citation markers', () {
    test('a numeric footnote marker is dropped', () {
      expect(
        normalizeForSpeech('Mao rejected the doctrine [12] in that winter.'),
        'Mao rejected the doctrine in that winter.',
      );
    });

    test('several markers are dropped', () {
      expect(normalizeForSpeech('He agreed [1] but later [2] recanted.'),
          'He agreed but later recanted.');
    });

    test('ranges and lists of markers', () {
      expect(normalizeForSpeech('As shown [3-5] and [1,2] here.'),
          'As shown and here.');
    });


    test('a citation before a full stop keeps the full stop', () {
      // Removing "[12]" used to leave "p. 45 .", and the isolated-dot cleanup
      // then deleted the orphan — costing the sentence its ending.
      expect(normalizeForSpeech('See p. 45 [12].'), 'See page 45.');
      expect(sanitizeForTts('See Chapter IV, No. 5, p. 45 [12].'),
          'See Chapter 4, number 5, page 45.');
    });

    test('non-numeric brackets are kept', () {
      // [sic] is read; [...] is an elision the listener should hear.
      expect(normalizeForSpeech('He said it was [sic] correct.'),
          'He said it was [sic] correct.');
      expect(normalizeForSpeech('Bohr [...] used the analogy.'),
          'Bohr [...] used the analogy.');
    });
  });

  group('addresses', () {
    test('a URL becomes its host, path dropped', () {
      expect(
        normalizeForSpeech('See https://www.example.com/a/b.html for it.'),
        'See example dot com for it.',
      );
    });

    test('a URL ending a sentence keeps the full stop', () {
      // THE BUG: the period sits on the path, which gets dropped.
      expect(
        normalizeForSpeech('Read https://example.com/x. Then stop.'),
        'Read example dot com. Then stop.',
      );
    });

    test('a bare domain with a path', () {
      expect(normalizeForSpeech('Read unicode.org/reports/tr29 today.'),
          'Read unicode dot org today.');
    });

    test('a parenthesised URL keeps its bracket', () {
      expect(normalizeForSpeech('(see https://example.org/x) and more.'),
          '(see example dot org) and more.');
    });

    test('an email is spoken as a person reads it', () {
      expect(normalizeForSpeech('Write to Jane.Doe@example.com about it.'),
          'Write to Jane Doe at example dot com about it.');
    });

    test('ordinary sentences are not mistaken for domains', () {
      // A run-on "word.Next" must not look like a hostname.
      const s = 'He left.Then she arrived.';
      expect(normalizeForSpeech(s), s);
      expect(normalizeForSpeech('All models are wrong. Some are useful.'),
          'All models are wrong. Some are useful.');
    });
  });

  group('abbreviations read as letters', () {
    test('expanded to words', () {
      expect(normalizeForSpeech('Some texts, e.g. the Analects, disagree.'),
          'Some texts, for example the Analects, disagree.');
      expect(normalizeForSpeech('The base, i.e. the peasantry, held.'),
          'The base, that is the peasantry, held.');
      expect(normalizeForSpeech('The ratio held, cf. Boorman 1969.'),
          'The ratio held, compare Boorman 1969.');
    });

    test('etc. keeps its period so the sentence still ends', () {
      expect(normalizeForSpeech('Apples, oranges, etc. Then he left.'),
          'Apples, oranges, et cetera. Then he left.');
    });

    test('capitalisation is carried over', () {
      expect(normalizeForSpeech('E.g. this one.'), 'For example this one.');
    });

    test('not expanded inside a word', () {
      expect(normalizeForSpeech('The gavs. file is here.'),
          'The gavs. file is here.');
    });
  });

  group('symbols', () {
    test('ampersand is spoken', () {
      expect(normalizeForSpeech('Pitt, Briggs & Co. at noon.'),
          'Pitt, Briggs and Co. at noon.');
    });

    test('underscores become spaces', () {
      expect(normalizeForSpeech('The awesome_content_final file.'),
          'The awesome content final file.');
    });
  });

  group('left alone on purpose', () {
    test('what espeak already reads correctly', () {
      // Verified against espeak-ng itself: bare integers, percentages,
      // ordinals, times and dotted acronyms need no help.
      for (final s in [
        'It ran from 1990 to 1995.',
        'He came 1st and she came 2nd.',
        'Support fell by 20% that year.',
        'They met at 12:30 pm.',
        'I work for the U.S. Government in Virginia.',
      ]) {
        expect(normalizeForSpeech(s), s, reason: s);
      }
    });

    test('normalising twice changes nothing further', () {
      const s = 'See [1] https://example.com/a, e.g. here & there.';
      final once = normalizeForSpeech(s);
      expect(normalizeForSpeech(once), once);
    });
  });

  group('the displayed text is untouched', () {
    test('cleanText does not normalise', () {
      const source = 'The doctrine [12] is at https://example.com/a, e.g. here.';
      // What the reader shows keeps every character.
      expect(cleanText(source), source);
      // What the engine hears does not.
      expect(sanitizeForTts(source),
          'The doctrine is at example dot com, for example here.');
    });
  });
}

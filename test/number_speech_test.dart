import 'package:flutter_test/flutter_test.dart';
import 'package:lu_ji/services/number_speech.dart';
import 'package:lu_ji/services/speech_normalizer.dart';

/// Expectations here are not taste — each was chosen by running espeak-ng, the
/// phonemiser Piper actually uses, and listening to what came back. The
/// comments record what the engine did with the *un*normalised form.
void main() {
  group('money', () {
    test('whole amounts', () {
      // espeak: "$100.00" -> "dollar one hundred zero zero"
      expect(normalizeNumbers(r'She has $100.00 in her bag.'),
          'She has 100 dollars in her bag.');
      expect(normalizeNumbers(r'It cost $5.'), 'It cost 5 dollars.');
    });

    test('one unit is singular', () {
      expect(normalizeNumbers(r'It cost $1.'), 'It cost 1 dollar.');
      expect(normalizeNumbers(r'Exactly £1.00 remained.'),
          'Exactly 1 pound remained.');
    });

    test('cents', () {
      expect(normalizeNumbers(r'The fare was $2.50 exactly.'),
          'The fare was 2 dollars and 50 cents exactly.');
      expect(normalizeNumbers(r'One penny: $0.01.'),
          'One penny: 0 dollars and 1 cent.');
    });

    test('magnitudes, spelled and abbreviated', () {
      // espeak: "$1.2 billion" -> "dollar one two billion"
      expect(normalizeNumbers(r'It cost $1.2 billion in total.'),
          'It cost 1 point 2 billion dollars in total.');
      expect(normalizeNumbers(r'A £5m programme.'),
          'A 5 million pounds programme.');
      expect(normalizeNumbers(r'Worth $4.2bn today.'),
          'Worth 4 point 2 billion dollars today.');
    });

    test('other currencies', () {
      expect(normalizeNumbers('It cost €3,000 last year.'),
          'It cost 3000 euros last year.');
      expect(normalizeNumbers('About ¥500 each.'), 'About 500 yen each.');
    });
  });

  group('dates', () {
    test('ISO', () {
      // espeak: "two thousand twenty six dash zero eight dash zero six"
      expect(normalizeNumbers('Recorded 2026-08-06, from interview.'),
          'Recorded the 6th of August 2026, from interview.');
    });

    test('numeric, read in US order', () {
      // A convention, not a deduction — a British 6/8/2026 would be read wrong.
      expect(normalizeNumbers('Dated 8/6/2026 in the file.'),
          'Dated August 6th, 2026 in the file.');
    });

    test('textual dates gain the ordinal that is actually spoken', () {
      expect(normalizeNumbers('On August 6, 2026 he wrote.'),
          'On August 6th, 2026 he wrote.');
      expect(normalizeNumbers('On Sept 1, 1939 it began.'),
          'On Sept 1st, 1939 it began.');
    });

    test('an impossible date is left alone', () {
      expect(normalizeNumbers('Ratio 13/45/2026 here.'),
          'Ratio 13/45/2026 here.');
    });
  });

  group('numbers', () {
    test('thousands separators are removed', () {
      // espeak: "1,000" -> "one zero zero zero"; "12,500" -> "twelve five hundred"
      expect(normalizeNumbers('About 1,000 people came.'),
          'About 1000 people came.');
      expect(normalizeNumbers('Some 12,500 in all.'), 'Some 12500 in all.');
    });

    test('decimals get an explicit point', () {
      // espeak drops the point entirely: "1.2" -> "one two"
      expect(normalizeNumbers('A factor of 1.2 applied.'),
          'A factor of 1 point 2 applied.');
    });

    test('fractional digits are read one at a time', () {
      expect(normalizeNumbers('Pi is 3.14 roughly.'),
          'Pi is 3 point 1 4 roughly.');
    });

    test('ranges are spoken as "to"', () {
      // espeak reads the hyphen aloud as "dash".
      expect(normalizeNumbers('Between 1990-1995 it held.'),
          'Between 1990 to 1995 it held.');
      expect(normalizeNumbers('Some 5-10 people were there.'),
          'Some 5 to 10 people were there.');
    });

    test('a separated range survives both rules', () {
      expect(normalizeNumbers('From 1,000-2,000 copies.'),
          'From 1000 to 2000 copies.');
    });
  });

  group('references', () {
    test('roman numerals behind a structural word', () {
      // espeak: "Chapter IV" -> "chapter roman four"
      expect(normalizeNumbers('As shown in Chapter IV of the work.'),
          'As shown in Chapter 4 of the work.');
      expect(normalizeNumbers('See Part XIV here.'), 'See Part 14 here.');
    });

    test('a bare roman numeral is not touched', () {
      // "I" is a pronoun far more often than a numeral.
      expect(normalizeNumbers('I went to see him.'), 'I went to see him.');
    });

    test('No. and page abbreviations', () {
      // espeak: "No. 5" -> "no five"
      expect(normalizeNumbers('You can find it at No. 5 today.'),
          'You can find it at number 5 today.');
      expect(normalizeNumbers('See p. 45 and pp. 60-64.'),
          'See page 45 and pages 60 to 64.');
    });
  });

  group('headings', () {
    test('a short chunk without terminal punctuation is closed', () {
      // A heading is a short paragraph with no full stop. Without one the
      // synthesiser trails off into whatever follows.
      expect(normalizeForSpeech('WHO I ANSWER TO'), 'WHO I ANSWER TO.');
      expect(normalizeForSpeech('Chapter Four'), 'Chapter Four.');
    });

    test('existing punctuation is respected', () {
      expect(normalizeForSpeech('Ends.'), 'Ends.');
      expect(normalizeForSpeech('Is it so?'), 'Is it so?');
      expect(normalizeForSpeech('Consider this:'), 'Consider this:');
      expect(normalizeForSpeech('and then,'), 'and then,');
    });

    test('a long paragraph is never given one', () {
      final long = 'a word that runs on and on ' * 5; // > 80 chars
      expect(normalizeForSpeech(long).endsWith('.'), isFalse);
    });
  });

  group('interaction', () {
    test('money inside a sentence with a citation and a date', () {
      expect(
        normalizeForSpeech(
            r'By 2026-08-06 [3] the fund held $1.2 billion, cf. p. 45.'),
        'By the 6th of August 2026 the fund held 1 point 2 billion dollars, '
        'compare page 45.',
      );
    });

    test('normalising twice changes nothing further', () {
      const s = r'On 2026-08-06 it cost $1,200.50 — see Chapter IV, No. 5.';
      final once = normalizeForSpeech(s);
      expect(normalizeForSpeech(once), once);
    });
  });
}

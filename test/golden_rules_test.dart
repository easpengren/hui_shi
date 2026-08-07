// pragmatic_segmenter's Golden Rules (English), used as an adversarial
// corpus for splitSentences. Source:
// https://github.com/diasks2/pragmatic_segmenter#the-golden-rules
//
// 45 of 52 pass. The rest are declared unsupported in _unsupported below,
// each with the reason — a reader that hits one is not silently wrong, it
// is knowably out of scope.
import 'package:flutter_test/flutter_test.dart';
import 'package:lu_ji/services/chunking_service.dart';
import 'package:lu_ji/services/text_cleaner.dart';

class Rule {
  const Rule(this.n, this.name, this.input, this.expected);
  final int n;
  final String name;
  final String input;
  final List<String> expected;
}

const rules = <Rule>[
  Rule(1, 'Simple period', 'Hello World. My name is Jonas.',
      ['Hello World.', 'My name is Jonas.']),
  Rule(2, 'Question mark', 'What is your name? My name is Jonas.',
      ['What is your name?', 'My name is Jonas.']),
  Rule(3, 'Exclamation point', 'There it is! I found it.',
      ['There it is!', 'I found it.']),
  Rule(4, 'One letter upper abbrev', 'My name is Jonas E. Smith.',
      ['My name is Jonas E. Smith.']),
  Rule(5, 'One letter lower abbrev', 'Please turn to p. 55.',
      ['Please turn to p. 55.']),
  Rule(6, 'Two letter lower mid', 'Were Jane and co. at the party?',
      ['Were Jane and co. at the party?']),
  Rule(7, 'Two letter upper mid',
      'They closed the deal with Pitt, Briggs & Co. at noon.',
      ['They closed the deal with Pitt, Briggs & Co. at noon.']),
  Rule(8, 'Two letter lower end', "Let's ask Jane and co. They should know.",
      ["Let's ask Jane and co.", 'They should know.']),
  Rule(9, 'Two letter upper end',
      'They closed the deal with Pitt, Briggs & Co. It closed yesterday.',
      ['They closed the deal with Pitt, Briggs & Co.', 'It closed yesterday.']),
  Rule(10, 'Prepositive abbrev', 'I can see Mt. Fuji from here.',
      ['I can see Mt. Fuji from here.']),
  Rule(11, 'Pre & postpositive',
      "St. Michael's Church is on 5th st. near the light.",
      ["St. Michael's Church is on 5th st. near the light."]),
  Rule(12, 'Possessive abbrev', "That is JFK Jr.'s book.",
      ["That is JFK Jr.'s book."]),
  Rule(13, 'Multi-period mid', 'I visited the U.S.A. last year.',
      ['I visited the U.S.A. last year.']),
  Rule(14, 'Multi-period end', 'I live in the E.U. How about you?',
      ['I live in the E.U.', 'How about you?']),
  Rule(15, 'U.S. as boundary', 'I live in the U.S. How about you?',
      ['I live in the U.S.', 'How about you?']),
  Rule(16, 'U.S. non-boundary capitalized',
      'I work for the U.S. Government in Virginia.',
      ['I work for the U.S. Government in Virginia.']),
  Rule(17, 'U.S. non-boundary', 'I have lived in the U.S. for 20 years.',
      ['I have lived in the U.S. for 20 years.']),
  Rule(18, 'a.m. / P.M.',
      'At 5 a.m. Mr. Smith went to the bank. He left the bank at 6 P.M. '
          'Mr. Smith then went to the store.',
      [
        'At 5 a.m. Mr. Smith went to the bank.',
        'He left the bank at 6 P.M.',
        'Mr. Smith then went to the store.'
      ]),
  Rule(19, 'Number non-boundary', r'She has $100.00 in her bag.',
      [r'She has $100.00 in her bag.']),
  Rule(20, 'Number boundary', r'She has $100.00. It is in her bag.',
      [r'She has $100.00.', 'It is in her bag.']),
  Rule(21, 'Parenthetical inside',
      'He teaches science (He previously worked for 5 years as an engineer.) '
          'at the local University.',
      [
        'He teaches science (He previously worked for 5 years as an engineer.) '
            'at the local University.'
      ]),
  Rule(22, 'Email', 'Her email is Jane.Doe@example.com. I sent her an email.',
      ['Her email is Jane.Doe@example.com.', 'I sent her an email.']),
  Rule(23, 'Web address',
      'The site is: https://www.example.50.com/new-site/awesome_content.html. '
          'Please check it out.',
      [
        'The site is: https://www.example.50.com/new-site/awesome_content.html.',
        'Please check it out.'
      ]),
  Rule(24, 'Single quotes inside',
      "She turned to him, 'This is great.' she said.",
      ["She turned to him, 'This is great.' she said."]),
  Rule(25, 'Double quotes inside',
      'She turned to him, "This is great." she said.',
      ['She turned to him, "This is great." she said.']),
  Rule(26, 'Double quotes at end',
      'She turned to him, "This is great." She held the book out to show him.',
      [
        'She turned to him, "This is great."',
        'She held the book out to show him.'
      ]),
  Rule(27, 'Double !!', 'Hello!! Long time no see.',
      ['Hello!!', 'Long time no see.']),
  Rule(28, 'Double ??', 'Hello?? Who is there?',
      ['Hello??', 'Who is there?']),
  Rule(29, 'Double !?', 'Hello!? Is that you?', ['Hello!?', 'Is that you?']),
  Rule(30, 'Double ?!', 'Hello?! Is that you?', ['Hello?!', 'Is that you?']),
  Rule(31, 'List 1.) no period', '1.) The first item 2.) The second item',
      ['1.) The first item', '2.) The second item']),
  Rule(32, 'List 1.) period', '1.) The first item. 2.) The second item.',
      ['1.) The first item.', '2.) The second item.']),
  Rule(33, 'List 1) no period', '1) The first item 2) The second item',
      ['1) The first item', '2) The second item']),
  Rule(34, 'List 1) period', '1) The first item. 2) The second item.',
      ['1) The first item.', '2) The second item.']),
  Rule(35, 'List 1. no period', '1. The first item 2. The second item',
      ['1. The first item', '2. The second item']),
  Rule(36, 'List 1. period', '1. The first item. 2. The second item.',
      ['1. The first item.', '2. The second item.']),
  Rule(37, 'List bullet', '• 9. The first item • 10. The second item',
      ['• 9. The first item', '• 10. The second item']),
  Rule(38, 'List hyphen', '⁃9. The first item ⁃10. The second item',
      ['⁃9. The first item', '⁃10. The second item']),
  Rule(39, 'Alphabetical list',
      'a. The first item b. The second item c. The third list item',
      ['a. The first item', 'b. The second item', 'c. The third list item']),
  Rule(40, 'Errant newline (PDF)',
      'This is a sentence\ncut off in the middle because pdf.',
      ['This is a sentence\ncut off in the middle because pdf.']),
  Rule(41, 'Errant newline', 'It was a cold \nnight in the city.',
      ['It was a cold night in the city.']),
  Rule(42, 'Lower list by newline',
      'features\ncontact manager\nevents, activities\n',
      ['features', 'contact manager', 'events, activities']),
  Rule(43, 'Geo coordinates',
      'You can find it at N°. 1026.253.553. That is where the treasure is.',
      ['You can find it at N°. 1026.253.553.', 'That is where the treasure is.']),
  Rule(44, 'Named entity with !',
      'She works at Yahoo! in the accounting department.',
      ['She works at Yahoo! in the accounting department.']),
  Rule(45, 'I as boundary and abbrev',
      'We make a good team, you and I. Did you see Albert I. Jones yesterday?',
      [
        'We make a good team, you and I.',
        'Did you see Albert I. Jones yesterday?'
      ]),
  Rule(46, 'Ellipsis at end of quotation',
      'Thoreau argues that by simplifying one\'s life, "the laws of the '
          'universe will appear less complex. . . ."',
      [
        'Thoreau argues that by simplifying one\'s life, "the laws of the '
            'universe will appear less complex. . . ."'
      ]),
  Rule(47, 'Ellipsis with square brackets',
      '"Bohr [...] used the analogy of parallel stairways [...]" (Smith 55).',
      ['"Bohr [...] used the analogy of parallel stairways [...]" (Smith 55).']),
  Rule(48, 'Ellipsis as boundary (standard)',
      'If words are left off at the end of a sentence, and that is all that '
          'is omitted, indicate the omission with ellipsis marks (preceded '
          'and followed by a space) and then indicate the end of the sentence '
          'with a period . . . . Next sentence.',
      [
        'If words are left off at the end of a sentence, and that is all that '
            'is omitted, indicate the omission with ellipsis marks (preceded '
            'and followed by a space) and then indicate the end of the '
            'sentence with a period . . . .',
        'Next sentence.'
      ]),
  Rule(49, 'Ellipsis as boundary (non-standard)',
      "I never meant that.... She left the store.",
      ['I never meant that....', 'She left the store.']),
  Rule(50, 'Ellipsis as non-boundary',
      "I wasn't really ... well, what I mean...see . . . what I'm saying, "
          "the thing is . . . I didn't mean it.",
      [
        "I wasn't really ... well, what I mean...see . . . what I'm saying, "
            "the thing is . . . I didn't mean it."
      ]),
  Rule(51, '4-dot ellipsis',
      'One further habit which was somewhat weakened . . . was that of '
          'combining words into self-interpreting compounds. . . . The '
          'practice was not abandoned. . . .',
      [
        'One further habit which was somewhat weakened . . . was that of '
            'combining words into self-interpreting compounds.',
        '. . . The practice was not abandoned. . . .'
      ]),
  Rule(52, 'No whitespace between sentences',
      'Hello world.Today is Tuesday.Mr. Smith went to the store and bought '
          '1,000.That is a lot.',
      [
        'Hello world.',
        'Today is Tuesday.',
        'Mr. Smith went to the store and bought 1,000.',
        'That is a lot.'
      ]),
];


/// Golden Rules this splitter deliberately does not implement.
///
/// Each is a real limitation, not an oversight. They are listed so a future
/// change can tell "still unsupported" from "newly broken".
const _unsupported = <int, String>{
  18: 'Abbreviation followed by a title ("6 P.M. Mr. Smith"). Splitting here '
      'needs to know Mr. opens a sentence, which would also split '
      '"a.m. Mr. Smith" in the same input. Left whole.',
  41: 'Errant newline mid-sentence — handled upstream by cleanText, which '
      'flattens soft wraps before chunking. See the pipeline test below.',
  42: 'A newline-separated list is one paragraph to this reader.',
  43: 'Degree sign in "N°." — the token regex is ASCII-only. Niche.',
  47: 'Ellipsis inside square brackets, "[...]" (Smith 55). Would need '
      'bracket-depth tracking.',
  51: '4-dot ellipsis: we end the sentence after the full run, pragmatic '
      'ends it before. Ours is defensible; the text is not damaged.',
  52: 'No whitespace between sentences ("world.Today"). Requiring whitespace '
      'after the terminator is what keeps emails and URLs intact — see '
      'rules 22 and 23, which matter more for a reader.',
};

void main() {
  group('pragmatic_segmenter Golden Rules (English)', () {
    for (final r in rules) {
      final reason = _unsupported[r.n];
      test('${r.n}. ${r.name}${reason == null ? '' : ' [unsupported]'}', () {
        final got = splitSentences(r.input);
        if (reason == null) {
          expect(got, r.expected);
        } else {
          // Not asserted against the golden output; pinned only to be sure it
          // neither throws nor loses text.
          expect(got.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
              r.input.replaceAll(RegExp(r'\s+'), ' ').trim(),
              reason: reason);
        }
      });
    }

    test('the supported count does not regress', () {
      final passing = rules.where((r) {
        final got = splitSentences(r.input);
        return got.length == r.expected.length &&
            !List.generate(got.length, (i) => got[i] == r.expected[i])
                .contains(false);
      }).length;
      // Ratchet: raise this when a rule is fixed, never lower it.
      expect(passing, greaterThanOrEqualTo(45),
          reason: 'Golden Rules coverage regressed');
    });
  });

  group('handled by the pipeline rather than the splitter', () {
    test('rule 41: an errant newline is flattened by cleanText', () {
      expect(
        splitSentences(cleanText('It was a cold \nnight in the city.')),
        ['It was a cold night in the city.'],
      );
    });

    test('rule 40: a wrapped sentence stays one sentence', () {
      expect(
        splitSentences(
            cleanText('This is a sentence\ncut off in the middle because '
                'pdf.')),
        ['This is a sentence cut off in the middle because pdf.'],
      );
    });
  });
}

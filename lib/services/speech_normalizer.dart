/// Rewriting text into what it should *sound* like.
///
/// This runs only on the way into a TTS engine — the reader displays the
/// original chunk, so nothing here changes a character on screen. That
/// separation is what makes it safe to be aggressive: expanding "e.g." to
/// "for example" would be wrong in the text and is right in the ear.
///
/// Numbers, money and dates are handled in `number_speech.dart`. An earlier
/// version of this file claimed the engines already did that; running espeak-ng
/// directly disproved it — `$100.00` was being read "dollar one hundred zero
/// zero" and `1,000` as "one zero zero zero".
library;

import 'number_speech.dart';

/// Abbreviations a synthesiser reads as letters ("ee jee") rather than words.
///
/// The trailing period is part of the key. It is kept in the replacement only
/// for `etc.`, which routinely ends a sentence — dropping it there would run
/// two sentences together. The rest are mid-sentence by nature.
const _spokenAbbreviations = <String, String>{
  'e.g.': 'for example',
  'i.e.': 'that is',
  'cf.': 'compare',
  'viz.': 'namely',
  'approx.': 'approximately',
  'vs.': 'versus',
  'etc.': 'et cetera.',
};

/// A citation marker: `[12]`, `[1,2]`, `[3-5]`. Purely numeric, so `[sic]` and
/// the elided-quotation `[...]` are left alone.
final _footnoteRegex = RegExp(r'\[\s*\d+(?:\s*[-,–]\s*\d+)*\s*\]');

/// Scheme-qualified, www-qualified, or a common TLD with an optional path.
/// The TLD list is what stops `word.Next` in a run-on sentence from looking
/// like a domain.
final _urlRegex = RegExp(
  r'\b(?:https?://|www\.)[^\s<>"]+'
  r'|\b[\w-]+(?:\.[\w-]+)*\.(?:com|org|net|edu|gov|mil|int|io|ai|dev|uk|de)'
  r'(?:/[^\s<>"]*)?',
  caseSensitive: false,
);

final _emailRegex = RegExp(r'\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b');

final _underscoreRegex = RegExp(r'_+');
final _whitespaceRegex = RegExp(r'\s+');

/// Rewrite [input] into a form a speech engine reads correctly.
String normalizeForSpeech(String input) {
  var text = input;

  // Emails before URLs: an address contains a domain, and the URL rule would
  // otherwise claim the half of it after the @.
  text = text.replaceAllMapped(_emailRegex, (m) => _spokenEmail(m.group(0)!));
  text = text.replaceAllMapped(_urlRegex, (m) => _spokenUrl(m.group(0)!));

  // A citation number interrupts the sentence it is attached to. Drop the
  // marker and the space it leaves behind.
  text = text.replaceAll(_footnoteRegex, '');

  text = normalizeNumbers(text);
  text = _expandAbbreviations(text);
  text = text.replaceAll('&', ' and ');
  text = text.replaceAll(_underscoreRegex, ' ');

  return _closeHeading(text.replaceAll(_whitespaceRegex, ' ').trim());
}

/// Longest a chunk can be and still be treated as a heading.
const _headingMaxLength = 80;

/// Give a heading the intonation of a finished statement.
///
/// Chunks are paragraphs, so a heading is a short paragraph with no terminal
/// punctuation — "ENDS", "Chapter Four", "Who I Answer To". Without a full stop
/// a synthesiser reads it with trailing, unfinished intonation and runs it into
/// whatever follows.
///
/// This is the reading-app treatment, not the screen-reader one: NVDA and JAWS
/// announce "heading level one", which is right for navigating an interface and
/// wrong for listening to a book. The heading is spoken as written, then
/// closed. Its own chunk already gives it an utterance boundary.
///
/// A trailing comma, colon, semicolon or dash is left alone — those already
/// carry prosody and signal that something follows.
String _closeHeading(String text) {
  if (text.isEmpty || text.length > _headingMaxLength) return text;
  final last = text[text.length - 1];
  if (!RegExp(r'[A-Za-z0-9)\]"' "'" r'”’]').hasMatch(last)) return text;
  return '$text.';
}

String _expandAbbreviations(String text) {
  var out = text;
  _spokenAbbreviations.forEach((abbrev, spoken) {
    final pattern = RegExp(
      '(?<![A-Za-z])${RegExp.escape(abbrev)}(?![A-Za-z])',
      caseSensitive: false,
    );
    out = out.replaceAllMapped(pattern, (m) {
      final matched = m.group(0)!;
      // "E.g." opening a sentence should still open one.
      final startsUpper = matched[0].toUpperCase() == matched[0] &&
          matched[0].toLowerCase() != matched[0];
      if (!startsUpper) return spoken;
      return spoken[0].toUpperCase() + spoken.substring(1);
    });
  });
  return out;
}

/// `https://www.example.com/a/b.html` -> `example dot com`.
///
/// The path is dropped outright. Nobody follows a URL by ear, and reading one
/// aloud in full is the single worst thing a reader can do to a sentence.
String _spokenUrl(String url) {
  // Punctuation at the end belongs to the sentence, not the address — and it
  // is usually attached to the *path*, so it has to come off before the path
  // is dropped or the sentence loses its full stop.
  final trailing = RegExp(r'[.,;:!?)\]]+$').firstMatch(url)?.group(0) ?? '';
  var host = url.substring(0, url.length - trailing.length);

  final scheme = host.indexOf('://');
  if (scheme != -1) host = host.substring(scheme + 3);
  final slash = host.indexOf('/');
  if (slash != -1) host = host.substring(0, slash);
  if (host.toLowerCase().startsWith('www.')) host = host.substring(4);

  return '${host.replaceAll('.', ' dot ').replaceAll(_whitespaceRegex, ' ')}'
      '$trailing';
}

/// `Jane.Doe@example.com` -> `Jane Doe at example dot com`.
String _spokenEmail(String email) {
  final at = email.lastIndexOf('@');
  final local = email.substring(0, at).replaceAll(RegExp(r'[._+-]+'), ' ');
  final domain = email.substring(at + 1).replaceAll('.', ' dot ');
  return '$local at $domain';
}

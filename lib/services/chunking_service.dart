import 'list_detector.dart';

const int kMaxChunkLength = 280;

/// Words that routinely end in a period without ending a sentence.
///
/// Stored without the trailing period and lower-cased. Dotted forms (`U.S.`,
/// `e.g.`) are not listed — they are caught by the "token contains a period"
/// rule in [_endsSentence], which generalises to acronyms nobody listed.
const _abbreviations = <String>{
  // Titles and ranks
  'mr', 'mrs', 'ms', 'dr', 'prof', 'sr', 'jr', 'st', 'rev', 'hon', 'fr',
  'gen', 'col', 'sgt', 'capt', 'lt', 'gov', 'sen', 'rep', 'pres', 'supt',
  'det', 'insp', 'messrs', 'atty', 'adm', 'maj', 'cmdr', 'esq', 'mt',
  // Latin and editorial
  'etc', 'vs', 'cf', 'al', 'ibid', 'viz', 'ca', 'approx', 'ed', 'eds',
  'trans', 'repr',
  // Organisations
  'inc', 'ltd', 'co', 'corp', 'dept', 'univ', 'assn', 'bros', 'dist',
  // Months and days
  'jan', 'feb', 'mar', 'apr', 'jun', 'jul', 'aug', 'sep', 'sept', 'oct',
  'nov', 'dec', 'mon', 'tue', 'tues', 'wed', 'thu', 'thur', 'thurs', 'fri',
  'sat', 'sun',
};

/// Reference abbreviations that are also ordinary words, so they only suppress
/// a split when a number follows.
///
/// `no` is the reason this set exists: listing it unconditionally meant
/// `He said "no." She left.` never split, because the citation form `No. 5`
/// and the word *no* are spelled the same.
const _numericAbbreviations = <String>{
  'no', 'nos', 'vol', 'vols', 'ch', 'chap', 'sec', 'fig', 'figs', 'pp',
  'para', 'art', 'pt',
};

final _digitOrRomanRegex = RegExp(r'[0-9ivxlcIVXLC]');

/// Words that commonly open a sentence.
///
/// These are what let an abbreviation still end a sentence: `Co. It closed`
/// splits, while `Co. at noon` and `U.S. Government` do not. Without this the
/// splitter could never end a sentence on an abbreviation at all.
const _sentenceStarters = <String>{
  'he', 'she', 'it', 'they', 'we', 'you', 'this', 'that', 'these',
  'those', 'there', 'then', 'here', 'did', 'do', 'does', 'how', 'what',
  'when', 'where', 'who', 'whom', 'whose', 'why', 'which', 'if', 'although',
  'though', 'however', 'nevertheless', 'moreover', 'therefore', 'thus',
  'meanwhile', 'later', 'finally', 'next', 'first', 'second', 'afterward',
  'still', 'yet', 'also', 'but', 'so', 'because', 'his', 'her', 'their',
  'our', 'my', 'your', 'its', 'no', 'yes', 'not', 'one', 'some', 'many',
  'most', 'each', 'every', 'both', 'another', 'such', 'let', 'now',
};

/// A candidate sentence end: a run of terminal punctuation (so `?!`, `!!` and
/// a spaced ellipsis `. . . .` are one unit), any closing quotes or brackets,
/// then whitespace.
///
/// Matching the whole run is what stops `. . . .` from being split into four
/// sentences that are each a single period — chunks TTS would either skip or
/// read aloud as punctuation.
final _terminatorRegex =
    RegExp(r'[.!?](?:[ \t]*[.!?])*["' "'" r'”’»)\]]*(?:\s+|$)');

/// The word immediately preceding a period, including any internal periods so
/// that `U.S` and `e.g` arrive intact.
final _tokenBeforeRegex = RegExp(r'([A-Za-z][A-Za-z.]*)$');

final _nextWordRegex = RegExp(r"^([A-Za-z][A-Za-z']*)");

final _lowercaseRegex = RegExp(r'[a-z]');


/// Split [text] into small, TTS-friendly chunks.
///
/// Sentence-first and deliberately small (see [kMaxChunkLength]) so playback
/// controls feel responsive and pause/resume lands near a boundary.
///
/// Three passes, in this order:
///
///  1. lines — a line break is a hard boundary, as it was before;
///  2. list items — `1.` and `2.` become separate chunks with their own pause
///     rather than one run-on (see list_detector.dart);
///  3. sentences — via [splitSentences], which does not break on abbreviations
///     or initials. The regex this replaced cut on any `[.!?]` plus a space, so
///     "George E. P. Box" was read as three fragments.
///
/// An over-long sentence still falls back to clause splitting and then to a
/// hard split, exactly as before.
List<String> chunkText(String text, {int maxLen = kMaxChunkLength}) {
  final normalized = text
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();
  if (normalized.isEmpty) return const [];

  final chunks = <String>[];
  for (final line in normalized.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    for (final item in splitListItems(trimmed)) {
      for (final sentence in splitSentences(item)) {
        _emit(sentence, maxLen, chunks);
      }
    }
  }
  return chunks.where((c) => c.isNotEmpty).toList(growable: false);
}

/// Add one sentence to [chunks], splitting it if it exceeds [maxLen].
void _emit(String sentence, int maxLen, List<String> chunks) {
  if (sentence.length <= maxLen) {
    chunks.add(sentence);
    return;
  }

  // Too long to say in one breath: break at clause punctuation, then — only as
  // a last resort — mid-word.
  final clauses = sentence.split(RegExp(r'(?<=[,，:：])\s*'));
  final buffer = StringBuffer();
  for (final clause in clauses) {
    final c = clause.trim();
    if (c.isEmpty) continue;

    if (buffer.length + c.length + 1 > maxLen && buffer.isNotEmpty) {
      chunks.add(buffer.toString().trim());
      buffer.clear();
    }

    if (c.length > maxLen) {
      var start = 0;
      while (start < c.length) {
        final end = (start + maxLen).clamp(0, c.length);
        chunks.add(c.substring(start, end).trim());
        start = end;
      }
      continue;
    }

    if (buffer.isNotEmpty) buffer.write(' ');
    buffer.write(c);
  }

  if (buffer.isNotEmpty) chunks.add(buffer.toString().trim());
}

/// Split [text] into sentences, without breaking on abbreviations or initials.
///
/// A chunk boundary is also a highlight boundary and an audible pause, so a
/// false split is much more costly than a missed one: breaking "George E. P.
/// Box" across three chunks stutters the name and fragments the highlight,
/// whereas running two sentences together only drops a pause. Every rule here
/// therefore biases toward *not* splitting when the evidence is ambiguous.
List<String> splitSentences(String text) {
  final items = splitListItems(text);
  if (items.length > 1) return items.expand(_sentencesWithin).toList();
  return _sentencesWithin(text);
}

List<String> _sentencesWithin(String text) {
  final sentences = <String>[];
  // The period in a leading "1." is part of the marker, not a sentence end.
  final markerEnd = leadingMarkerLength(text);
  var start = 0;

  for (final match in _terminatorRegex.allMatches(text)) {
    if (match.start < markerEnd) continue;
    if (!_endsSentence(text, match)) continue;
    // Keep the punctuation with the sentence; drop the trailing whitespace.
    final end = match.start + match.group(0)!.trimRight().length;
    final sentence = text.substring(start, end).trim();
    if (sentence.isNotEmpty) sentences.add(sentence);
    start = match.end;
  }

  final tail = text.substring(start).trim();
  if (tail.isNotEmpty) sentences.add(tail);
  return sentences;
}

bool _endsSentence(String text, RegExpMatch match) {
  final index = match.start;

  // A following lower-case word means the thought continues — this keeps
  // '"Stop!" he said.' and "U.S. for 20 years" in one piece.
  final next = _firstNonSpace(text, match.end);
  if (next == null) return true;
  if (_lowercaseRegex.hasMatch(next)) return false;

  if (text[index] != '.') return true;

  // A period with whitespace before it is a spaced ellipsis ("the thing is
  // . . . I didn't mean it"), never the end of a word. Only a following
  // sentence-opener makes it a boundary — which is what separates
  // ". . . . Next sentence." from ". . . I didn't mean it."
  if (index > 0 && RegExp(r'\s').hasMatch(text[index - 1])) {
    return _startsNewSentence(text, match.end);
  }

  final token =
      _tokenBeforeRegex.firstMatch(text.substring(0, index))?.group(1);
  if (token == null) return true;

  final lower = token.toLowerCase();
  final isAcronym = _isDottedAcronym(token);
  final isInitial = token.length == 1;
  final isAbbrev = _abbreviations.contains(lower);

  if (_numericAbbreviations.contains(lower) &&
      _digitOrRomanRegex.hasMatch(next)) {
    // "No. 5" is a citation; 'He said "no."' is a sentence.
    return false;
  }

  if (isAcronym || isInitial || isAbbrev) {
    // An abbreviation can still end a sentence. The next word decides:
    // "Co. It closed" ends one, "U.S. Government" and "E. Smith" do not.
    return _startsNewSentence(text, match.end);
  }

  return true;
}

/// True for `U.S`, `e.g`, `a.m`, `U.S.A` — every dot-separated piece is one or
/// two characters.
///
/// The length test is what keeps `example.com` and `awesome_content.html` out:
/// treating any dotted token as an acronym meant a sentence ending in an email
/// address or URL never ended.
bool _isDottedAcronym(String token) {
  if (!token.contains('.')) return false;
  return token
      .split('.')
      .where((part) => part.isNotEmpty)
      .every((part) => part.length <= 2);
}

bool _startsNewSentence(String text, int from) {
  final word = _nextWordRegex.firstMatch(text.substring(from))?.group(1);
  // Not a word at all — a number, most often. "Please turn to p. 55" and
  // "vol. 3" continue; treating a following number as a new sentence split
  // every citation in two.
  if (word == null) return false;
  return _sentenceStarters.contains(word.toLowerCase());
}

String? _firstNonSpace(String text, int from) {
  for (var i = from; i < text.length; i++) {
    if (!RegExp(r'\s').hasMatch(text[i])) return text[i];
  }
  return null;
}

List<String> _splitBySentence(String text, int maxLen) {
  final sentences = splitSentences(text);
  final chunks = <String>[];
  final buffer = StringBuffer();

  for (final sentence in sentences) {
    if (buffer.length + sentence.length + 1 > maxLen && buffer.isNotEmpty) {
      chunks.add(buffer.toString().trim());
      buffer.clear();
    }
    if (buffer.isNotEmpty) buffer.write(' ');
    buffer.write(sentence);
  }

  if (buffer.isNotEmpty) chunks.add(buffer.toString().trim());
  return chunks.where((c) => c.isNotEmpty).toList();
}

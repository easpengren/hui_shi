/// Recognising list items so each one reads as its own chunk.
///
/// A list item is a unit of speech: it wants its own highlight, its own pause,
/// and its own tap-to-seek target. Left undetected, `1. The first item 2. The
/// second item` is either one long chunk or — worse — gets cut by sentence
/// rules into a chunk that is just `1.`, which TTS reads as punctuation or
/// skips entirely.
///
/// Detection is deliberately conservative, because the failure mode is severe.
/// `He was born in 1990. The war ended in 1991. Peace came.` contains two
/// numbered "markers" with prose between them and would be shredded by a naive
/// detector. Three guards prevent that:
///
///  1. **The run must start at the beginning of the text.** Lists start blocks;
///     a number in mid-sentence does not. This alone rejects the 1990/1991 case
///     and, usefully, `George E. P. Box` — whose first candidate marker is not
///     at index 0.
///  2. **Values must be consecutive and of one kind** — `1, 2, 3` or `a, b, c`,
///     with the same terminator throughout. `E.` then `P.` is not a sequence.
///  3. **Items must have content.** `John A. B. Smith` has nothing between its
///     two candidates, so it is not a list.
///
/// Bullets are exempt from the sequence rule — `•` is unambiguous in a way a
/// digit never is.
library;

/// Bullets trusted anywhere, including mid-paragraph.
const _strictBullets = '•‣▪▫◦⁃●○∙';

/// Also treated as bullets, but only at the start of a line, where a dash
/// cannot be prose punctuation.
const _lineOnlyBullets = r'\-–—*+';

/// Minimum characters between two markers for them to be list items.
const _minItemLength = 4;

/// A candidate marker: an optional bullet, an optional value plus terminator.
/// Group 1 bullet, 2/3 value+terminator after a bullet, 4/5 a bare value.
final _candidateRegex = RegExp(
  '(?:^|\\s)(?:'
  '([$_strictBullets])\\s*(?:([0-9]{1,2}|[A-Za-z])([.)]{1,2}))?'
  '|'
  '([0-9]{1,2}|[A-Za-z])([.)]{1,2})'
  ')(?=\\s)',
);

/// The same, anchored, for line-start detection — dashes and asterisks allowed.
final _lineStartMarkerRegex = RegExp(
  '^[ \\t]*(?:'
  '[$_strictBullets$_lineOnlyBullets]\\s*(?:[0-9]{1,3}|[A-Za-z])?[.)]{0,2}'
  '|'
  '(?:[0-9]{1,3}|[A-Za-z])[.)]{1,2}'
  ')\\s+\\S',
);

class _Candidate {
  _Candidate(this.start, this.bullet, this.value, this.terminator);

  /// Index of the marker itself, past any leading whitespace.
  final int start;
  final String? bullet;
  final String? value;
  final String? terminator;

  bool get isBulleted => bullet != null;

  /// `1` -> 1, `a` -> 1, `B` -> 2. Null when there is no value.
  int? get ordinal {
    final v = value;
    if (v == null) return null;
    final n = int.tryParse(v);
    if (n != null) return n;
    return v.toLowerCase().codeUnitAt(0) - 'a'.codeUnitAt(0) + 1;
  }

  /// Digits and letters must not be mixed within one list.
  String get kind {
    final v = value;
    if (v == null) return 'bullet';
    return int.tryParse(v) != null ? 'digit' : 'alpha';
  }
}

/// True when [line] opens with a list marker.
///
/// Used by `cleanText` to keep list items on separate lines instead of
/// unwrapping them into the preceding paragraph — the common real-document
/// case, where every item already sits on its own line.
bool startsWithListMarker(String line) =>
    _lineStartMarkerRegex.hasMatch(line);

/// Length of a leading list marker in [text], or 0.
///
/// Sentence splitting uses this to ignore the period in `1.` — otherwise the
/// marker becomes a sentence of its own.
int leadingMarkerLength(String text) {
  final match = _candidateRegex.matchAsPrefix(text);
  if (match == null) return 0;
  return match.end;
}

/// Split [text] into list items, or return `[text]` when it is not a list.
List<String> splitListItems(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return [text];

  final candidates = _candidatesIn(trimmed);
  if (candidates.length < 2) return [text];

  // Guard 1: a list starts at the start.
  if (candidates.first.start != 0) return [text];

  final run = _longestValidRun(candidates, trimmed);
  if (run.length < 2) return [text];

  final items = <String>[];
  for (var i = 0; i < run.length; i++) {
    final end = i + 1 < run.length ? run[i + 1].start : trimmed.length;
    final item = trimmed.substring(run[i].start, end).trim();
    if (item.isNotEmpty) items.add(item);
  }
  return items.isEmpty ? [text] : items;
}

List<_Candidate> _candidatesIn(String text) {
  final out = <_Candidate>[];
  for (final m in _candidateRegex.allMatches(text)) {
    // Skip the leading whitespace the pattern consumed.
    var start = m.start;
    while (start < m.end && _isSpace(text[start])) {
      start++;
    }
    out.add(_Candidate(
      start,
      m.group(1),
      m.group(2) ?? m.group(4),
      m.group(3) ?? m.group(5),
    ));
  }
  return out;
}

/// The longest prefix run of [candidates] that behaves like one list.
List<_Candidate> _longestValidRun(List<_Candidate> candidates, String text) {
  final run = <_Candidate>[candidates.first];

  for (var i = 1; i < candidates.length; i++) {
    final prev = run.last;
    final next = candidates[i];

    // Guard 3: an item needs content.
    final between = text.substring(prev.start, next.start).trim();
    if (between.length < _minItemLength) break;

    if (next.kind != prev.kind) break;
    if (next.terminator != prev.terminator) break;
    if (next.isBulleted != prev.isBulleted) break;

    // Guard 2: consecutive values. Bullets carry no ordinal to compare, and
    // a bullet is unambiguous enough not to need one.
    final a = prev.ordinal;
    final b = next.ordinal;
    if (a != null && b != null && b != a + 1) break;
    if ((a == null) != (b == null)) break;

    run.add(next);
  }

  return run;
}

bool _isSpace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';

/// Rewriting numbers, money and dates into what they should sound like.
///
/// Every rule here was chosen by running the *actual* phonemiser Piper uses
/// (espeak-ng, via piper-phonemize) over the input and reading the result.
/// espeak handles bare integers, percentages and ordinals correctly and needs
/// no help with them. It gets these badly wrong:
///
/// ```
///   1,000        -> "one zero zero zero"          (thousands separator)
///   12,500       -> "twelve five hundred"
///   1.2          -> "one two"                     (decimal point dropped)
///   $100.00      -> "dollar one hundred zero zero" (symbol read first)
///   $1.2 billion -> "dollar one two billion"
///   2026-08-06   -> "two thousand twenty six dash zero eight dash zero six"
///   1990-1995    -> "...ninety dash nineteen..."
///   Chapter IV   -> "chapter roman four"
///   No. 5        -> "no five"
/// ```
///
/// The strategy is to *restructure rather than spell*: emit `100 dollars`, not
/// `one hundred dollars`, because espeak says "one hundred dollars" for the
/// former. That avoids carrying a number-to-words speller and keeps the output
/// correct for the system TTS engine too, which does its own normalisation.
///
/// The one thing restructuring cannot fix is the decimal point, which espeak
/// simply drops — so `1.2` is written out as `1 point 2`.
library;

const _months = <String>[
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const _monthPattern = 'January|February|March|April|May|June|July|August|'
    'September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept?|'
    'Oct|Nov|Dec';

const _currencyNames = <String, List<String>>{
  // symbol: [singular, plural]
  r'$': ['dollar', 'dollars'],
  '£': ['pound', 'pounds'],
  '€': ['euro', 'euros'],
  '¥': ['yen', 'yen'],
  '₹': ['rupee', 'rupees'],
};

const _magnitudes = <String, String>{
  'k': 'thousand',
  'm': 'million',
  'bn': 'billion',
  'tn': 'trillion',
  'thousand': 'thousand',
  'million': 'million',
  'billion': 'billion',
  'trillion': 'trillion',
};

final _romanRegex = RegExp(
  r'\b(Chapter|Part|Book|Volume|Vol\.?|Act|Scene|Section|Appendix)'
  r'\s+([IVXLCDM]+)\b',
);

final _isoDateRegex = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');
final _numericDateRegex = RegExp(r'\b(\d{1,2})/(\d{1,2})/(\d{4})\b');
final _textualDateRegex = RegExp('\\b($_monthPattern)\\s+(\\d{1,2})(,?)\\s+(\\d{4})\\b');

final _currencyRegex = RegExp(
  r'([$£€¥₹])\s?(\d[\d,]*(?:\.\d+)?)'
  r'(?:\s*(k|m|bn|tn|thousand|million|billion|trillion)\b)?',
  caseSensitive: false,
);

final _numberAbbrevRegex =
    RegExp(r'\b(No|Nos|pp|p)\.\s*(?=\d)', caseSensitive: false);
final _thousandsRegex = RegExp(r'\b(\d{1,3}(?:,\d{3})+)\b');
final _rangeRegex = RegExp(r'\b(\d+)\s*[-–—]\s*(\d+)\b');
final _decimalRegex = RegExp(r'\b(\d+)\.(\d+)\b');

/// Rewrite numeric, monetary and date expressions in [input].
String normalizeNumbers(String input) {
  var text = input;

  // Dates first: an ISO date owns hyphens the range rule would otherwise
  // claim, and a numeric date owns slashes.
  text = text.replaceAllMapped(_isoDateRegex, (m) {
    final month = _monthName(int.parse(m.group(2)!));
    if (month == null) return m.group(0)!;
    return 'the ${_ordinal(int.parse(m.group(3)!))} of $month ${m.group(1)}';
  });

  // US order (month/day/year) — this is a convention, not a deduction. A
  // British source using day/month would be read wrong, and nothing in the
  // text says which it is.
  text = text.replaceAllMapped(_numericDateRegex, (m) {
    final month = _monthName(int.parse(m.group(1)!));
    final day = int.parse(m.group(2)!);
    if (month == null || day < 1 || day > 31) return m.group(0)!;
    return '$month ${_ordinal(day)}, ${m.group(3)}';
  });

  // "August 6, 2026" is read "August six ..."; the ordinal is how it is said.
  text = text.replaceAllMapped(_textualDateRegex, (m) {
    final day = int.parse(m.group(2)!);
    if (day < 1 || day > 31) return m.group(0)!;
    return '${m.group(1)} ${_ordinal(day)}, ${m.group(4)}';
  });

  text = text.replaceAllMapped(_currencyRegex, _spokenMoney);

  text = text.replaceAllMapped(_romanRegex, (m) {
    final value = _fromRoman(m.group(2)!);
    return value == null ? m.group(0)! : '${m.group(1)} $value';
  });

  text = text.replaceAllMapped(_numberAbbrevRegex, (m) {
    switch (m.group(1)!.toLowerCase()) {
      case 'no':
        return 'number ';
      case 'nos':
        return 'numbers ';
      case 'pp':
        return 'pages ';
      default:
        return 'page ';
    }
  });

  // Separators before ranges: "1,000-2,000" must not be read as "000 to 2".
  text = text.replaceAllMapped(
      _thousandsRegex, (m) => m.group(1)!.replaceAll(',', ''));
  text = text.replaceAllMapped(_rangeRegex, (m) => '${m.group(1)} to ${m.group(2)}');
  text = text.replaceAllMapped(
      _decimalRegex, (m) => '${m.group(1)} point ${_digits(m.group(2)!)}');

  return text;
}

String _spokenMoney(Match match) {
  final names = _currencyNames[match.group(1)!];
  if (names == null) return match.group(0)!;
  final amount = match.group(2)!.replaceAll(',', '');
  final magnitude = match.group(3) == null
      ? null
      : _magnitudes[match.group(3)!.toLowerCase()];

  final dot = amount.indexOf('.');
  final whole = dot == -1 ? amount : amount.substring(0, dot);
  final fraction = dot == -1 ? '' : amount.substring(dot + 1);

  if (magnitude != null) {
    // "$1.2 billion" — the fraction is part of the quantity, not cents.
    final quantity =
        fraction.isEmpty ? whole : '$whole point ${_digits(fraction)}';
    return '$quantity $magnitude ${names[1]}';
  }

  // Two fractional digits are cents; anything else is a decimal quantity.
  if (fraction.length == 2) {
    final cents = int.tryParse(fraction) ?? 0;
    final unit = whole == '1' ? names[0] : names[1];
    if (cents == 0) return '$whole $unit';
    return '$whole $unit and $cents ${cents == 1 ? 'cent' : 'cents'}';
  }
  if (fraction.isNotEmpty) {
    return '$whole point ${_digits(fraction)} ${names[1]}';
  }
  return '$whole ${whole == '1' ? names[0] : names[1]}';
}

/// Fractional digits are read one at a time: "3.14" is "three point one four",
/// never "three point fourteen".
String _digits(String fraction) => fraction.split('').join(' ');

String? _monthName(int month) =>
    month >= 1 && month <= 12 ? _months[month - 1] : null;

String _ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

const _romanValues = <String, int>{
  'I': 1, 'V': 5, 'X': 10, 'L': 50, 'C': 100, 'D': 500, 'M': 1000,
};

/// Null when [input] is not a well-formed numeral — "I" as a pronoun reaches
/// here only behind a structural word like "Chapter", but "Part MMX" should
/// still be left alone rather than guessed at.
int? _fromRoman(String input) {
  var total = 0;
  var previous = 0;
  for (final char in input.split('').reversed) {
    final value = _romanValues[char];
    if (value == null) return null;
    if (value < previous) {
      total -= value;
    } else {
      total += value;
      previous = value;
    }
  }
  return total > 0 && total < 5000 ? total : null;
}

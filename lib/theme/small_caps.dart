import 'package:flutter/material.dart';

class SmallCapsText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const SmallCapsText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final base =
        (style ?? Theme.of(context).textTheme.labelMedium)?.copyWith(
          letterSpacing: 1.4,
        ) ??
        const TextStyle(fontSize: 13, letterSpacing: 1.4);

    final minSize = (base.fontSize ?? 13).clamp(13, 200).toDouble();
    final reduced = base.copyWith(fontSize: minSize * 0.82, letterSpacing: 1.1);

    final spans = <InlineSpan>[];
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final upper = char.toUpperCase();
      final isLowerLatin = char != upper && RegExp(r'[a-z]').hasMatch(char);
      spans.add(TextSpan(text: upper, style: isLowerLatin ? reduced : base));
    }

    return RichText(
      text: TextSpan(style: base, children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

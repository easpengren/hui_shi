import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Legge uses a calm, scholarly palette.
///
/// Light — parchment cream background, deep ink text, muted gold accent.
/// Dark  — deep navy background, warm off-white text, muted gold accent.
class AppTheme {
  static const _ink = Color(0xFF1A242B);
  static const _prussian = Color(0xFF1F5975);
  static const _celadon = Color(0xFF9CCFC3);
  static const _cinnabar = Color(0xFFC04A2A);
  static const _paper = Color(0xFFF2EDE2);
  static const _paperBright = Color(0xFFFBF8F1);
  static const _paperLine = Color(0xFFC7BCAB);
  static const _muted = Color(0xFF5C666A);
  static const _night = Color(0xFF11181C);
  static const _nightSurface = Color(0xFF182126);
  static const _errorRed = Color(0xFFD24A3A);

  // ── Light theme ─────────────────────────────────────────────────────────────

  static ThemeData get light {
    final globalFontFamily = GoogleFonts.zenKakuGothicAntique().fontFamily;

    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: _prussian,
      onPrimary: _paperBright,
      secondary: _celadon,
      onSecondary: _ink,
      error: _errorRed,
      onError: Colors.white,
      surface: _paperBright,
      onSurface: _ink,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _paper,
    );

    final textTheme = TextTheme(
      displaySmall: GoogleFonts.zenKakuGothicAntique(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: _ink,
        height: 1.15,
      ),
      headlineMedium: GoogleFonts.zenKakuGothicAntique(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: _ink,
        height: 1.2,
      ),
      headlineSmall: GoogleFonts.zenKakuGothicAntique(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: _ink,
        height: 1.3,
      ),
      titleMedium: GoogleFonts.zenKakuGothicAntique(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: _ink,
      ),
      titleSmall: GoogleFonts.zenKakuGothicAntique(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: _muted,
        letterSpacing: 0.5,
      ),
      bodyLarge: GoogleFonts.zenKakuGothicAntique(
        fontSize: 18,
        color: _ink,
        height: 1.65,
      ),
      bodyMedium: GoogleFonts.zenKakuGothicAntique(
        fontSize: 15,
        color: _muted,
        height: 1.6,
      ),
      bodySmall: GoogleFonts.zenKakuGothicAntique(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: _prussian,
        letterSpacing: 0.6,
      ),
      labelMedium: GoogleFonts.zenKakuGothicAntique(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: _ink,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: globalFontFamily,
      scaffoldBackgroundColor: _paper,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: _paper,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: _paperBright,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _paperLine, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(color: _paperLine, space: 1),
      iconTheme: const IconThemeData(color: _ink, size: 22),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _paperBright,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _paperLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _paperLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _prussian, width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _paper,
        side: const BorderSide(color: _paperLine),
        labelStyle: GoogleFonts.zenKakuGothicAntique(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: _muted,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _cinnabar,
        foregroundColor: _paperBright,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _cinnabar,
          foregroundColor: _paperBright,
          textStyle: GoogleFonts.zenKakuGothicAntique(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _cinnabar,
          textStyle: GoogleFonts.zenKakuGothicAntique(
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? _cinnabar : _paperLine,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? _cinnabar.withValues(alpha: 0.35)
              : _paperLine.withValues(alpha: 0.5),
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(cursorColor: _prussian),
      extensions: base.extensions.values,
    );
  }

  // ── Dark theme ──────────────────────────────────────────────────────────────

  static ThemeData get dark {
    final globalFontFamily = GoogleFonts.zenKakuGothicAntique().fontFamily;

    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: _celadon,
      onPrimary: _night,
      secondary: _prussian,
      onSecondary: _paperBright,
      error: Color(0xFFEF5350),
      onError: _night,
      surface: _nightSurface,
      onSurface: _paperBright,
    );

    final textTheme = TextTheme(
      displaySmall: GoogleFonts.zenKakuGothicAntique(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: _paperBright,
        height: 1.15,
      ),
      headlineMedium: GoogleFonts.zenKakuGothicAntique(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: _paperBright,
        height: 1.2,
      ),
      headlineSmall: GoogleFonts.zenKakuGothicAntique(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: _paperBright,
        height: 1.3,
      ),
      titleMedium: GoogleFonts.zenKakuGothicAntique(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: _paperBright,
      ),
      titleSmall: GoogleFonts.zenKakuGothicAntique(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: const Color(0xFF9AA6A8),
        letterSpacing: 0.5,
      ),
      bodyLarge: GoogleFonts.zenKakuGothicAntique(
        fontSize: 18,
        color: _paperBright,
        height: 1.65,
      ),
      bodyMedium: GoogleFonts.zenKakuGothicAntique(
        fontSize: 15,
        color: const Color(0xFFB4C1C2),
        height: 1.6,
      ),
      bodySmall: GoogleFonts.zenKakuGothicAntique(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: _celadon,
        letterSpacing: 0.6,
      ),
      labelMedium: GoogleFonts.zenKakuGothicAntique(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: _paperBright,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: globalFontFamily,
      scaffoldBackgroundColor: _night,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: _night,
        foregroundColor: _paperBright,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: _nightSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF344548), width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF344548), space: 1),
      iconTheme: const IconThemeData(color: _paperBright, size: 22),
      chipTheme: ChipThemeData(
        backgroundColor: _nightSurface,
        side: const BorderSide(color: Color(0xFF344548)),
        labelStyle: GoogleFonts.zenKakuGothicAntique(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: const Color(0xFFB4C1C2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _cinnabar,
        foregroundColor: _paperBright,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _cinnabar,
          foregroundColor: _paperBright,
          textStyle: GoogleFonts.zenKakuGothicAntique(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFE66B4A),
          textStyle: GoogleFonts.zenKakuGothicAntique(
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? _cinnabar
              : const Color(0xFF5B6769),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? _cinnabar.withValues(alpha: 0.35)
              : const Color(0xFF344548),
        ),
      ),
    );
  }
}

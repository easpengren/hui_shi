import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const _ink = Color(0xFF1A242B);
  static const _prussian = Color(0xFF1F5975);
  static const _celadon = Color(0xFF9CCFC3);
  static const _cinnabar = Color(0xFFC04A2A);
  static const _paper = Color(0xFFF2EDE2);
  static const _paperBright = Color(0xFFFBF8F1);
  static const _paperLine = Color(0xFFC7BCAB);
  static const _night = Color(0xFF2A2520);
  static const _nightSurface = Color(0xFF38312A);
  static const _errorRed = Color(0xFFD24A3A);

  static final _lightScheme = const ColorScheme(
    brightness: Brightness.light,
    primary: _prussian,
    onPrimary: _paperBright,
    primaryContainer: _prussian,
    onPrimaryContainer: _paperBright,
    secondary: _celadon,
    onSecondary: _ink,
    secondaryContainer: _prussian,
    onSecondaryContainer: _paperBright,
    error: _errorRed,
    onError: Colors.white,
    surface: _paperBright,
    onSurface: _ink,
  );

  static final _darkScheme = const ColorScheme(
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

  static TextTheme _textTheme(TextTheme base, Color body) {
    return GoogleFonts.zenKakuGothicAntiqueTextTheme(base).copyWith(
      displaySmall: const TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        height: 1.15,
      ),
      headlineMedium: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
      headlineSmall: const TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      titleSmall: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      bodyLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        height: 1.65,
        color: body,
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: body,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.6,
        color: body,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: body,
      ),
    );
  }

  static ThemeData get light {
    final t = ThemeData(useMaterial3: true, colorScheme: _lightScheme);
    return t.copyWith(
      scaffoldBackgroundColor: _paper,
      textTheme: _textTheme(t.textTheme, _ink),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: _paper,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: _paperBright,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _paperLine),
        ),
      ),
      dividerTheme: const DividerThemeData(space: 1, thickness: 1, color: _ink),
      iconTheme: const IconThemeData(size: 22),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _paperBright,
        isDense: true,
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
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _cinnabar,
          foregroundColor: _paperBright,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _cinnabar,
        foregroundColor: _paperBright,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _cinnabar),
      ),
      chipTheme: t.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: _paperLine),
        ),
        side: const BorderSide(color: _paperLine),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        backgroundColor: _paper,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? _cinnabar : _paperLine,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.selected)) return _prussian;
            return _paperBright;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.selected)) return _paperBright;
            return _ink;
          }),
          side: WidgetStateProperty.all(const BorderSide(color: _paperLine)),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(height: 68),
    );
  }

  static ThemeData get dark {
    final t = ThemeData(useMaterial3: true, colorScheme: _darkScheme);
    return t.copyWith(
      scaffoldBackgroundColor: _night,
      textTheme: _textTheme(t.textTheme, _paperBright),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: _night,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: _nightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF344548)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        space: 1,
        thickness: 1,
        color: Color(0xFF344548),
      ),
      iconTheme: const IconThemeData(size: 22),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Color(0xFFE66B4A)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _cinnabar,
      ),
      navigationBarTheme: const NavigationBarThemeData(height: 68),
    );
  }
}

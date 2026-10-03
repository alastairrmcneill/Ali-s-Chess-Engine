import 'package:flutter/material.dart';

class AppTheme {
  static const Color seed = Color(0xFF5B8DEF);

  static const Color lightSquare = Color(0xFFDEE3E6);
  static const Color darkSquare = Color(0xFF8CA2AD);
  static const Color highlight = Color(0xB3F6E05E);
  static const Color moveHint = Color(0x66222B33);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark).copyWith(
      surface: const Color(0xFF14181D),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: CardThemeData(
        color: const Color(0xFF1C222A),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }
}

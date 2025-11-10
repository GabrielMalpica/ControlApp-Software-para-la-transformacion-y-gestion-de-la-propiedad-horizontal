import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF006C3C);
  static const Color background = Color(0xFFF8FAF7);
  static const Color yellow = Color(0xFFF4C542);
  static const Color red = Color(0xFFE04F3F);
  static const Color green = Color(0xFF2E7D32);

  static ThemeData get lightTheme => ThemeData(
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(seedColor: primary),
        appBarTheme: const AppBarTheme(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          ),
        ),
      );
}

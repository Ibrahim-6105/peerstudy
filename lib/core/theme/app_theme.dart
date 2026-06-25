// Core app theme definitions for PeerStudy.
// This file keeps the dark color palette and common text styles.

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFF2A4D9A);
  static const Color background = Color(0xFF090B16);
  static const Color surface = Color(0xFF12162A);
  static const Color accent = Color(0xFF3C8DFF);
  static const Color danger = Color(0xFFEA4C4C);
  static const Color success = Color(0xFF4AD17D);

  // Defines the shared dark visual style used by all PeerStudy screens.
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: surface,
        error: danger,
      ),
      appBarTheme: const AppBarTheme(backgroundColor: surface, elevation: 0),
      cardTheme: const CardThemeData(
        color: Color(0xFF111429),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
        elevation: 2,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0F1222),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white24),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        bodyMedium: TextStyle(fontSize: 15, height: 1.4),
        bodySmall: TextStyle(fontSize: 13, color: Colors.white70),
      ),
    );
  }
}

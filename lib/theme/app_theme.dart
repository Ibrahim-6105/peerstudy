// This file contains PeerStudy's one shared light and dark design.
//
// Beginner note:
// A ThemeData object lets every Flutter screen reuse the same colors, text
// sizes, fields, cards, and buttons. Changing this file updates the whole app.

// Material supplies ThemeData and all common visual component themes.
import 'package:flutter/material.dart';

// Services supplies SystemUiOverlayStyle for the phone status/navigation bars.
import 'package:flutter/services.dart';

// AppTheme is a utility class, not a widget that appears on a page.
class AppTheme {
  // A private constructor prevents accidental AppTheme() objects.
  AppTheme._();

  // Blue shade 900 is the exact main color requested for PeerStudy.
  static const Color primary = Color(0xFF0D47A1);

  // The dark theme uses a lighter blue so actions stay readable at night.
  static const Color darkPrimary = Color(0xFF90CAF9);

  // Light pages and surfaces are deliberately pure white.
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);

  // Shared semantic colors keep success and error messages consistent.
  static const Color success = Color(0xFF16834B);
  static const Color danger = Color(0xFFB3261E);

  // One gentle radius makes cards and forms feel friendly without looking busy.
  static const double radius = 12;

  // Large screens keep readable line lengths instead of stretching content.
  static const double contentWidth = 980;

  // Main screens use calm, compact edge spacing on a normal phone.
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(16, 14, 16, 24);

  // These colors belong only to the light interface.
  static const Color _lightText = Color(0xFF172033);
  static const Color _lightMutedText = Color(0xFF58677E);
  static const Color _lightOutline = Color(0xFFD7E1EF);
  static const Color _lightSoftSurface = Color(0xFFF5F8FD);

  // These colors belong only to the dark interface.
  static const Color _darkBackground = Color(0xFF09111F);
  static const Color _darkSurface = Color(0xFF111C2E);
  static const Color _darkSoftSurface = Color(0xFF17243A);
  static const Color _darkOutline = Color(0xFF2D405C);
  static const Color _darkText = Color(0xFFF2F6FC);
  static const Color _darkMutedText = Color(0xFFB2BED0);

  // Light pages need dark system icons over the white phone bars.
  static const SystemUiOverlayStyle lightSystemUiOverlayStyle =
      SystemUiOverlayStyle(
        statusBarColor: background,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: background,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: _lightOutline,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarContrastEnforced: false,
      );

  // Dark pages need light system icons over the navy phone bars.
  static const SystemUiOverlayStyle darkSystemUiOverlayStyle =
      SystemUiOverlayStyle(
        statusBarColor: _darkBackground,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: _darkBackground,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: _darkOutline,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarContrastEnforced: false,
      );

  // The light theme is the default appearance for a fresh installation.
  static ThemeData get lightTheme {
    // The exact ColorScheme feeds colors to all Material 3 widgets.
    const colors = ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFE7F0FD),
      onPrimaryContainer: Color(0xFF082D6B),
      secondary: Color(0xFF3267B3),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFEDF3FC),
      onSecondaryContainer: Color(0xFF1B3B69),
      surface: surface,
      surfaceContainerLow: Color(0xFFFAFCFF),
      surfaceContainerHighest: _lightSoftSurface,
      onSurface: _lightText,
      onSurfaceVariant: _lightMutedText,
      outline: _lightOutline,
      error: danger,
      onError: Colors.white,
    );

    // Start with the common Material 3 foundation.
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colors,
      primaryColor: primary,
      scaffoldBackgroundColor: background,
      dividerColor: _lightOutline,
    );

    // copyWith applies PeerStudy's compact component choices.
    return base.copyWith(
      // Status and navigation bars blend into the white page safely.
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: _lightText,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
        titleTextStyle: TextStyle(
          color: _lightText,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        systemOverlayStyle: lightSystemUiOverlayStyle,
      ),

      // Cards stay white and use one quiet border instead of strong shadows.
      cardTheme: const CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          side: BorderSide(color: _lightOutline),
        ),
      ),

      // Dialogs inherit the same calm blue-and-white visual language.
      dialogTheme: const DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        titleTextStyle: TextStyle(
          color: _lightText,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          color: _lightMutedText,
          fontSize: 13,
          height: 1.4,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),

      // Bottom sheets are preferred for comfortable phone forms.
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        modalBarrierColor: Color(0x5209182E),
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      // Dense inputs reduce visual noise while leaving a comfortable tap area.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _lightSoftSurface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 12,
        ),
        labelStyle: const TextStyle(fontSize: 13, color: _lightMutedText),
        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF7A879A)),
        errorStyle: const TextStyle(fontSize: 11, height: 1.2),
        prefixIconColor: _lightMutedText,
        suffixIconColor: _lightMutedText,
        border: _inputBorder(_lightOutline),
        enabledBorder: _inputBorder(_lightOutline),
        focusedBorder: _inputBorder(primary, width: 1.5),
        errorBorder: _inputBorder(danger),
        focusedErrorBorder: _inputBorder(danger, width: 1.5),
      ),

      // Primary buttons use blue shade 900 and compact text.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFB7C5D8),
          disabledForegroundColor: Colors.white,
          minimumSize: const Size(48, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape: _buttonShape(),
        ),
      ),

      // FilledButton receives the same appearance as ElevatedButton.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape: _buttonShape(),
        ),
      ),

      // Secondary buttons remain quiet white controls with a blue border.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          side: const BorderSide(color: Color(0xFFB9CAE2)),
          shape: _buttonShape(),
        ),
      ),

      // Text buttons use the same blue without adding another filled surface.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          shape: _buttonShape(),
        ),
      ),

      // Navigation uses blue only for the selected destination.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFFE5EFFC),
        height: 66,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? primary
                : _lightMutedText,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? primary
                : _lightMutedText,
            size: 22,
          );
        }),
      ),

      // Older BottomNavigationBar screens receive the matching colors.
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: _lightMutedText,
        selectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: TextStyle(fontSize: 11),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // List rows and controls stay compact across settings and forms.
      listTileTheme: const ListTileThemeData(
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        titleTextStyle: TextStyle(
          color: _lightText,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(
          color: _lightMutedText,
          fontSize: 12,
          height: 1.35,
        ),
        iconColor: primary,
      ),

      // Reuse one smaller, quieter type scale everywhere.
      textTheme: _compactTextTheme(
        base.textTheme,
        textColor: _lightText,
        mutedColor: _lightMutedText,
      ),
    );
  }

  // The dark theme preserves the layout while changing only readable colors.
  static ThemeData get darkTheme {
    // Dark surfaces use the same blue identity with accessible foregrounds.
    const colors = ColorScheme.dark(
      primary: darkPrimary,
      onPrimary: Color(0xFF052A54),
      primaryContainer: Color(0xFF173B67),
      onPrimaryContainer: Color(0xFFD9E9FF),
      secondary: Color(0xFFAAC7EE),
      onSecondary: Color(0xFF102D50),
      secondaryContainer: Color(0xFF203D61),
      onSecondaryContainer: Color(0xFFDDEAFF),
      surface: _darkSurface,
      surfaceContainerLow: Color(0xFF0E1929),
      surfaceContainerHighest: _darkSoftSurface,
      onSurface: _darkText,
      onSurfaceVariant: _darkMutedText,
      outline: _darkOutline,
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
    );

    // Create the Material 3 dark foundation.
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colors,
      primaryColor: darkPrimary,
      scaffoldBackgroundColor: _darkBackground,
      dividerColor: _darkOutline,
    );

    // Apply the same compact layout as light mode.
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: _darkBackground,
        foregroundColor: _darkText,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
        titleTextStyle: TextStyle(
          color: _darkText,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        systemOverlayStyle: darkSystemUiOverlayStyle,
      ),
      cardTheme: const CardThemeData(
        color: _darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          side: BorderSide(color: _darkOutline),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: _darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        titleTextStyle: TextStyle(
          color: _darkText,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          color: _darkMutedText,
          fontSize: 13,
          height: 1.4,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _darkSurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: _darkSurface,
        modalBarrierColor: Color(0x99000000),
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkSoftSurface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 12,
        ),
        labelStyle: const TextStyle(fontSize: 13, color: _darkMutedText),
        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF8796AC)),
        errorStyle: const TextStyle(fontSize: 11, height: 1.2),
        prefixIconColor: _darkMutedText,
        suffixIconColor: _darkMutedText,
        border: _inputBorder(_darkOutline),
        enabledBorder: _inputBorder(_darkOutline),
        focusedBorder: _inputBorder(darkPrimary, width: 1.5),
        errorBorder: _inputBorder(const Color(0xFFFFB4AB)),
        focusedErrorBorder: _inputBorder(const Color(0xFFFFB4AB), width: 1.5),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: darkPrimary,
          foregroundColor: const Color(0xFF052A54),
          minimumSize: const Size(48, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape: _buttonShape(),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: const Color(0xFF052A54),
          minimumSize: const Size(48, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape: _buttonShape(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkPrimary,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          side: const BorderSide(color: _darkOutline),
          shape: _buttonShape(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkPrimary,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          shape: _buttonShape(),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _darkSurface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFF1D416D),
        height: 66,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? darkPrimary
                : _darkMutedText,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? darkPrimary
                : _darkMutedText,
            size: 22,
          );
        }),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: _darkSurface,
        selectedItemColor: darkPrimary,
        unselectedItemColor: _darkMutedText,
        selectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: TextStyle(fontSize: 11),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        titleTextStyle: TextStyle(
          color: _darkText,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(
          color: _darkMutedText,
          fontSize: 12,
          height: 1.35,
        ),
        iconColor: darkPrimary,
      ),
      textTheme: _compactTextTheme(
        base.textTheme,
        textColor: _darkText,
        mutedColor: _darkMutedText,
      ),
    );
  }

  // Build one rounded input border from a supplied theme color.
  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  // Build one shared rounded button shape.
  static RoundedRectangleBorder _buttonShape() {
    return RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
  }

  // Reduce the default Material type sizes without harming readability.
  static TextTheme _compactTextTheme(
    TextTheme base, {
    required Color textColor,
    required Color mutedColor,
  }) {
    return base.copyWith(
      headlineLarge: TextStyle(
        color: textColor,
        fontSize: 26,
        height: 1.18,
        fontWeight: FontWeight.w800,
      ),
      headlineMedium: TextStyle(
        color: textColor,
        fontSize: 23,
        height: 1.2,
        fontWeight: FontWeight.w800,
      ),
      headlineSmall: TextStyle(
        color: textColor,
        fontSize: 19,
        height: 1.25,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: TextStyle(
        color: textColor,
        fontSize: 17,
        height: 1.25,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: textColor,
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: TextStyle(
        color: textColor,
        fontSize: 13,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(
        color: textColor,
        fontSize: 14,
        height: 1.42,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: TextStyle(
        color: mutedColor,
        fontSize: 13,
        height: 1.42,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: TextStyle(
        color: mutedColor,
        fontSize: 12,
        height: 1.36,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: TextStyle(
        color: textColor,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: TextStyle(
        color: mutedColor,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: TextStyle(
        color: mutedColor,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

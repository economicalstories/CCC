import 'package:flutter/material.dart';

class ThemeConfig {
  static const double minFontSize = 12.0;
  static const double maxFontSize = 120.0;
  static const double defaultFontSize = 32.0;

  // High contrast colors
  static const Color lightBackground = Colors.white;
  static const Color lightText = Colors.black;
  static const Color darkBackground = Colors.black;
  static const Color darkText = Colors.white;

  static const Color primaryColor = Color(0xFF2196F3); // Accessible blue
  static const Color errorColor = Color(0xFFD32F2F);

  static ThemeData getLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: lightBackground,

      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: primaryColor,
        surface: lightBackground,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: lightText,
        onError: Colors.white,
      ),

      // App bar theme - more compact
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBackground,
        foregroundColor: lightText,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 48, // Reduced from default 56
      ),

      // Compact text theme - use smaller default sizes
      textTheme: const TextTheme(
        // Reduced sizes across the board for vertical space optimization
        displayLarge:
            TextStyle(fontSize: 32, fontWeight: FontWeight.w300, height: 1.1),
        displayMedium:
            TextStyle(fontSize: 28, fontWeight: FontWeight.w300, height: 1.1),
        displaySmall:
            TextStyle(fontSize: 24, fontWeight: FontWeight.w400, height: 1.1),
        headlineLarge:
            TextStyle(fontSize: 22, fontWeight: FontWeight.w400, height: 1.2),
        headlineMedium:
            TextStyle(fontSize: 20, fontWeight: FontWeight.w400, height: 1.2),
        headlineSmall:
            TextStyle(fontSize: 18, fontWeight: FontWeight.w500, height: 1.2),
        titleLarge:
            TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.3),
        titleMedium:
            TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.3),
        titleSmall:
            TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.3),
        bodyLarge:
            TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.3),
        bodyMedium:
            TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.3),
        bodySmall:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w400, height: 1.3),
        labelLarge:
            TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.3),
        labelMedium:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w500, height: 1.3),
        labelSmall:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w500, height: 1.3),
      ).apply(bodyColor: lightText, displayColor: lightText),

      // Compact button themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 8), // Reduced padding
          minimumSize: const Size(64, 32), // Smaller minimum size
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      // Compact icon theme
      iconTheme: const IconThemeData(
        color: lightText,
        size: 20, // Slightly smaller icons
      ),
    );
  }

  static ThemeData getDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: darkBackground,

      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: primaryColor,
        surface: darkBackground,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: darkText,
        onError: Colors.white,
      ),

      // App bar theme - more compact
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        foregroundColor: darkText,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 48, // Reduced from default 56
      ),

      // Compact text theme - use smaller default sizes
      textTheme: const TextTheme(
        // Reduced sizes across the board for vertical space optimization
        displayLarge:
            TextStyle(fontSize: 32, fontWeight: FontWeight.w300, height: 1.1),
        displayMedium:
            TextStyle(fontSize: 28, fontWeight: FontWeight.w300, height: 1.1),
        displaySmall:
            TextStyle(fontSize: 24, fontWeight: FontWeight.w400, height: 1.1),
        headlineLarge:
            TextStyle(fontSize: 22, fontWeight: FontWeight.w400, height: 1.2),
        headlineMedium:
            TextStyle(fontSize: 20, fontWeight: FontWeight.w400, height: 1.2),
        headlineSmall:
            TextStyle(fontSize: 18, fontWeight: FontWeight.w500, height: 1.2),
        titleLarge:
            TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.3),
        titleMedium:
            TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.3),
        titleSmall:
            TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.3),
        bodyLarge:
            TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.3),
        bodyMedium:
            TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.3),
        bodySmall:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w400, height: 1.3),
        labelLarge:
            TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.3),
        labelMedium:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w500, height: 1.3),
        labelSmall:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w500, height: 1.3),
      ).apply(bodyColor: darkText, displayColor: darkText),

      // Compact button themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 8), // Reduced padding
          minimumSize: const Size(64, 32), // Smaller minimum size
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      // Compact icon theme
      iconTheme: const IconThemeData(
        color: darkText,
        size: 20, // Slightly smaller icons
      ),
    );
  }

  // Caption text styling (separate from UI text) - more compact
  static TextStyle getCaptionTextStyle(double fontSize, Color textColor) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      color: textColor,
      height: 1.2, // Reduced from 1.4 for tighter line spacing
      fontFamily: 'Roboto',
    );
  }
}

import 'package:flutter/material.dart';

class ThemeConfig {
  static const double minFontSize = 16.0;
  static const double maxFontSize = 120.0;
  static const double defaultFontSize = 48.0;

  // High contrast colors
  static const Color lightBackground = Colors.white;
  static const Color lightText = Colors.black;
  static const Color darkBackground = Colors.black;
  static const Color darkText = Colors.white;

  static const Color primaryColor = Color(0xFF2196F3); // Accessible blue
  static const Color errorColor = Color(0xFFD32F2F);

  static ThemeData getLightTheme(double fontSize) {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: lightBackground,

      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: primaryColor,
        background: lightBackground,
        surface: lightBackground,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onBackground: lightText,
        onSurface: lightText,
        onError: Colors.white,
      ),

      // App bar theme
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBackground,
        foregroundColor: lightText,
        elevation: 0,
        centerTitle: true,
      ),

      // Text theme with large sizes
      textTheme: _getTextTheme(fontSize, lightText),

      // Button themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(200, 80),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          textStyle:
              TextStyle(fontSize: fontSize * 0.4, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),

      // Icon theme
      iconTheme: IconThemeData(
        color: lightText,
        size: fontSize * 0.6,
      ),
    );
  }

  static ThemeData getDarkTheme(double fontSize) {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: darkBackground,

      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: primaryColor,
        background: darkBackground,
        surface: darkBackground,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onBackground: darkText,
        onSurface: darkText,
        onError: Colors.white,
      ),

      // App bar theme
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        foregroundColor: darkText,
        elevation: 0,
        centerTitle: true,
      ),

      // Text theme with large sizes
      textTheme: _getTextTheme(fontSize, darkText),

      // Button themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(200, 80),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          textStyle:
              TextStyle(fontSize: fontSize * 0.4, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),

      // Icon theme
      iconTheme: IconThemeData(
        color: darkText,
        size: fontSize * 0.6,
      ),
    );
  }

  static TextTheme _getTextTheme(double baseFontSize, Color textColor) {
    return TextTheme(
      // Caption text (main display)
      displayLarge: TextStyle(
        fontSize: baseFontSize,
        fontWeight: FontWeight.w500,
        color: textColor,
        height: 1.4,
        fontFamily: 'Roboto',
      ),

      // UI text
      headlineMedium: TextStyle(
        fontSize: baseFontSize * 0.5,
        fontWeight: FontWeight.bold,
        color: textColor,
        fontFamily: 'Roboto',
      ),

      bodyLarge: TextStyle(
        fontSize: baseFontSize * 0.4,
        fontWeight: FontWeight.normal,
        color: textColor,
        fontFamily: 'Roboto',
      ),

      labelLarge: TextStyle(
        fontSize: baseFontSize * 0.35,
        fontWeight: FontWeight.w500,
        color: textColor,
        fontFamily: 'Roboto',
      ),
    );
  }
}

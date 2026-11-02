import 'package:flutter/material.dart';

/// Provides the visual styling, typography, and dark-mode palette for Pixel
/// Control Center, aligned with Google Material 3 guidelines.
abstract final class AppTheme {
  /// Primary brand color inspired by Google Pixel accent hues.
  static const Color primary = Color(0xFF8AB4F8);

  /// Secondary complementary accent color.
  static const Color secondary = Color(0xFF81C995);

  /// Deep slate surface background color for desktop windows.
  static const Color background = Color(0xFF1E1F22);

  /// Elevated card surface color.
  static const Color surface = Color(0xFF2B2D31);

  /// Accent highlight color for active USB connections.
  static const Color usbColor = Color(0xFF34A853);

  /// Accent highlight color for active Wi-Fi connections.
  static const Color wifiColor = Color(0xFF4285F4);

  /// Returns the configured dark [ThemeData] for desktop windows.
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surface,
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 2,
        margin: EdgeInsets.all(8),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }
}

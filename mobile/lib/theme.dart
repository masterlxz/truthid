import 'package:flutter/material.dart';

// Mesma identidade visual do site (docs/src/css/custom.css) e do desktop
// (App.css) — fundo quase preto, acento ciano, Space Grotesk nos títulos.
class AppColors {
  static const background = Color(0xFF0B0F14);
  static const surface = Color(0xFF111820);
  static const surfaceAlt = Color(0xFF161F2A);
  static const border = Color(0xFF1F2630);

  static const accent = Color(0xFF4DD0E1);
  static const accentDark = Color(0xFF34C3D6);

  static const textPrimary = Color(0xFFE6EDF3);
  static const textMuted = Color(0xFF9FB1C2);

  static const success = Color(0xFF4CAF7D);
  static const successBg = Color(0xFF13261F);
  static const danger = Color(0xFFE25C5C);
  static const dangerBg = Color(0xFF2A1518);
  static const warning = Color(0xFFE2B25C);
  static const warningBg = Color(0xFF2A2315);
  static const info = Color(0xFF5CA9E2);
  static const infoBg = Color(0xFF15212A);
}

final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.background,
  fontFamily: 'Inter',
  colorScheme: const ColorScheme.dark(
    surface: AppColors.background,
    primary: AppColors.accent,
    onPrimary: AppColors.background,
    secondary: AppColors.accent,
    error: AppColors.danger,
    onSurface: AppColors.textPrimary,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    headlineMedium: TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    headlineSmall: TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    titleLarge: TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    titleMedium: TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w500, color: AppColors.textPrimary),
    bodyLarge: TextStyle(color: AppColors.textPrimary),
    bodyMedium: TextStyle(color: AppColors.textPrimary),
    bodySmall: TextStyle(color: AppColors.textMuted),
    labelLarge: TextStyle(color: AppColors.textPrimary),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.background,
    foregroundColor: AppColors.textPrimary,
    elevation: 0,
    titleTextStyle: TextStyle(
      fontFamily: 'SpaceGrotesk',
      fontWeight: FontWeight.w600,
      fontSize: 20,
      color: AppColors.textPrimary,
    ),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: AppColors.surface,
    selectedItemColor: AppColors.accent,
    unselectedItemColor: AppColors.textMuted,
  ),
  cardTheme: CardThemeData(
    color: AppColors.surface,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: AppColors.border),
    ),
  ),
  dividerTheme: const DividerThemeData(color: AppColors.border),
  iconTheme: const IconThemeData(color: AppColors.textMuted),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.background,
      disabledBackgroundColor: AppColors.surfaceAlt,
      disabledForegroundColor: AppColors.textMuted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.textPrimary,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: AppColors.accent),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: AppColors.surfaceAlt,
    labelStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
    side: const BorderSide(color: AppColors.border),
  ),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: AppColors.surfaceAlt,
    contentTextStyle: TextStyle(color: AppColors.textPrimary),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surface,
    hintStyle: const TextStyle(color: AppColors.textMuted),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.accent),
    ),
  ),
);

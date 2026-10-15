import 'package:flutter/material.dart';

class AppColors {
  AppColors._();
  static const bg = Color(0xFFF4F8F8);
  static const ink = Color(0xFF0B2A3C);
  static const teal = Color(0xFF0E6F7E);
  static const coral = Color(0xFFFF6B57);
  static const mist = Color(0xFFCFE3E6);
  static const muted = Color(0xFF506B78);
  static const line = Color(0xFFE3ECEE);
  static const danger = Color(0xFFB3261E);
  static const okBg = Color(0xFFD7F0DC);
  static const warnBg = Color(0xFFFFF1C9);
  static const newBg = Color(0xFFFFE1DC);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.teal,
    onPrimary: Colors.white,
    secondary: AppColors.coral,
    onSecondary: AppColors.ink,
    surface: Colors.white,
    onSurface: AppColors.ink,
    error: AppColors.danger,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 24,
        fontWeight: FontWeight.w800,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.mist,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(
        const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.coral,
        foregroundColor: AppColors.ink,
        disabledBackgroundColor: AppColors.line,
        minimumSize: const Size(88, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Кнопка второго плана (тёмная), как «Принять в работу» в админке.
ButtonStyle darkButtonStyle({double height = 44}) => FilledButton.styleFrom(
  backgroundColor: AppColors.ink,
  foregroundColor: Colors.white,
  minimumSize: Size(0, height),
  padding: const EdgeInsets.symmetric(horizontal: 18),
);

/// Светлая кнопка («Позвонить», «Отмена»).
ButtonStyle lightButtonStyle({double height = 56}) => FilledButton.styleFrom(
  backgroundColor: AppColors.line,
  foregroundColor: AppColors.ink,
  minimumSize: Size(0, height),
  padding: const EdgeInsets.symmetric(horizontal: 20),
);

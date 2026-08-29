import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.paper,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.skyBlue,
      primary: AppColors.skyBlue,
      onPrimary: AppColors.ink,
      primaryContainer: AppColors.sky,
      onPrimaryContainer: AppColors.skyBlueDeep,
      secondary: AppColors.lime,
      onSecondary: AppColors.ink,
      secondaryContainer: AppColors.limeSoft,
      onSecondaryContainer: AppColors.limeDeep,
      tertiary: AppColors.limeDeep,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.limeSoft,
      onTertiaryContainer: AppColors.ink,
      surface: AppColors.receipt,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.muted,
      outline: AppColors.muted,
      outlineVariant: AppColors.line,
      surfaceTint: Colors.transparent,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.receipt,
      foregroundColor: AppColors.ink,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: AppColors.receipt,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusMedium),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.receipt,
      hintStyle: const TextStyle(color: AppColors.muted),
      border: _inputBorder(AppColors.lime),
      enabledBorder: _inputBorder(AppColors.lime),
      focusedBorder: _inputBorder(AppColors.skyBlueDeep, width: 1.5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.skyBlue,
        foregroundColor: AppColors.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusSmall),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.skyBlueDeep),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.skyBlueDeep,
        side: const BorderSide(color: AppColors.lime),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.skyBlue,
      foregroundColor: AppColors.ink,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.skyBlueDeep,
      linearTrackColor: AppColors.sky,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceMuted,
      selectedColor: AppColors.sky,
      checkmarkColor: AppColors.skyBlueDeep,
      labelStyle: const TextStyle(color: AppColors.ink),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: BorderSide.none,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return AppColors.line;
        return states.contains(WidgetState.selected) ? AppColors.skyBlue : null;
      }),
      checkColor: const WidgetStatePropertyAll(AppColors.limeDeep),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.skyBlue,
      inactiveTrackColor: AppColors.surfaceMuted,
      thumbColor: AppColors.skyBlueDeep,
      valueIndicatorColor: AppColors.sky,
      valueIndicatorTextStyle: TextStyle(color: AppColors.ink),
    ),
  );

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusSmall),
        borderSide: BorderSide(color: color, width: width),
      );
}

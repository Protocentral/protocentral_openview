import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_shapes.dart';
import 'signal_colors.dart';

/// ProtoCentral Design System v3 ("Signal Amber") → Material 3.
///
/// Source: /Users/akw/Downloads/ProtoCentral Design System (2).zip
///         references/colors_and_type.css
class AppTheme {
  AppTheme._();

  // === Brand (locked from logo) ===
  static const Color pcBrandBlue = Color(0xFF2C6E84);
  static const Color pcBrandBlueDk = Color(0xFF1F4E5E);
  static const Color pcBrandBlueLt = Color(0xFFC9DEE6);
  static const Color pcBrandGrey = Color(0xFF7A7E80);

  // === Accent — Signal Amber ===
  static const Color pcAccent = Color(0xFFF59E0B);
  static const Color pcAccentDk = Color(0xFFB45309);
  static const Color pcAccentLt = Color(0xFFFEF3C7);
  static const Color pcAccentOn = Color(0xFF1F1300);

  static ThemeData light() => _build(_lightScheme, SignalColors.light);
  static ThemeData dark() => _build(_darkScheme, SignalColors.dark);

  static final ColorScheme _lightScheme = const ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF2C6E84),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFC9DEE6),
    onPrimaryContainer: Color(0xFF0A2933),
    secondary: Color(0xFFB45309),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFFEF3C7),
    onSecondaryContainer: Color(0xFF1F1300),
    tertiary: Color(0xFF4338CA),
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFE0E7FF),
    onTertiaryContainer: Color(0xFF1E1B4B),
    error: Color(0xFFDC2626),
    onError: Colors.white,
    errorContainer: Color(0xFFFEE2E2),
    onErrorContainer: Color(0xFF450A0A),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF1A1F22),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F8F9),
    surfaceContainer: Color(0xFFF1F3F4),
    surfaceContainerHigh: Color(0xFFE7EAEC),
    surfaceContainerHighest: Color(0xFFDDE1E3),
    surfaceTint: Color(0xFF2C6E84),
    onSurfaceVariant: Color(0xFF5A6266),
    outline: Color(0xFF7A8388),
    outlineVariant: Color(0xFFB7BDC0),
    inverseSurface: Color(0xFF1A1F22),
    onInverseSurface: Color(0xFFF7F8F9),
    inversePrimary: Color(0xFF8FC6D9),
    scrim: Colors.black,
    shadow: Colors.black,
  );

  static final ColorScheme _darkScheme = const ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF6FB3CC),
    onPrimary: Color(0xFF002935),
    primaryContainer: Color(0xFF1F4E5E),
    onPrimaryContainer: Color(0xFFC9DEE6),
    secondary: Color(0xFFFBBF24),
    onSecondary: Color(0xFF1F1300),
    secondaryContainer: Color(0xFF4A2A03),
    onSecondaryContainer: Color(0xFFFEF3C7),
    tertiary: Color(0xFF818CF8),
    onTertiary: Color(0xFF1E1B4B),
    tertiaryContainer: Color(0xFF3730A3),
    onTertiaryContainer: Color(0xFFE0E7FF),
    error: Color(0xFFF87171),
    onError: Color(0xFF450A0A),
    errorContainer: Color(0xFF450A0A),
    onErrorContainer: Color(0xFFFEE2E2),
    surface: Color(0xFF131A1E),
    onSurface: Color(0xFFF1F4F6),
    surfaceContainerLowest: Color(0xFF0E1418),
    surfaceContainerLow: Color(0xFF161D22),
    surfaceContainer: Color(0xFF1B232A),
    surfaceContainerHigh: Color(0xFF232C33),
    surfaceContainerHighest: Color(0xFF2B353D),
    surfaceTint: Color(0xFF6FB3CC),
    onSurfaceVariant: Color(0xFFC5CCD0),
    outline: Color(0xFF8C9498),
    outlineVariant: Color(0xFF3A444A),
    inverseSurface: Color(0xFFF7F8F9),
    onInverseSurface: Color(0xFF1A1F22),
    inversePrimary: Color(0xFF2C6E84),
    scrim: Colors.black,
    shadow: Colors.black,
  );

  static ThemeData _build(ColorScheme scheme, SignalColors signals) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: scheme.surface,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme, scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: GoogleFonts.jost(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: scheme.surfaceTint,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: AppShapes.cardShape,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: AppShapes.buttonShape,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.jost(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle:
              GoogleFonts.jost(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: AppShapes.buttonShape,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        selectedLabelTextStyle: GoogleFonts.jost(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: GoogleFonts.jost(
          color: scheme.onSurfaceVariant,
        ),
        indicatorColor: scheme.secondaryContainer,
        useIndicator: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: scheme.surfaceTint,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.jost(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: AppShapes.brSm),
        labelStyle: GoogleFonts.jost(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: AppShapes.brSm,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppShapes.brSm,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppShapes.brSm,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      extensions: [signals],
    );
  }

  static TextTheme _textTheme(TextTheme base, ColorScheme scheme) {
    final display = GoogleFonts.sairaTextTheme(base);
    final body = GoogleFonts.montserratTextTheme(base);
    final ui = GoogleFonts.jostTextTheme(base);
    return base.copyWith(
      displayLarge: display.displayLarge?.copyWith(
          fontWeight: FontWeight.w700, fontSize: 57, height: 1.05),
      displayMedium: display.displayMedium?.copyWith(
          fontWeight: FontWeight.w700, fontSize: 45, height: 1.08),
      displaySmall: display.displaySmall?.copyWith(
          fontWeight: FontWeight.w700, fontSize: 36, height: 1.10),
      headlineLarge: ui.headlineLarge?.copyWith(
          fontWeight: FontWeight.w600, fontSize: 32, height: 1.18),
      headlineMedium: ui.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600, fontSize: 28, height: 1.22),
      headlineSmall: ui.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600, fontSize: 24, height: 1.30),
      titleLarge: ui.titleLarge?.copyWith(
          fontWeight: FontWeight.w600, fontSize: 22, height: 1.30),
      titleMedium: ui.titleMedium?.copyWith(
          fontWeight: FontWeight.w600, fontSize: 16, height: 1.40),
      titleSmall: ui.titleSmall?.copyWith(
          fontWeight: FontWeight.w600, fontSize: 14, height: 1.40),
      bodyLarge: body.bodyLarge?.copyWith(fontSize: 16, height: 1.55),
      bodyMedium: body.bodyMedium?.copyWith(fontSize: 14, height: 1.55),
      bodySmall: body.bodySmall?.copyWith(fontSize: 12, height: 1.50),
      labelLarge: ui.labelLarge?.copyWith(
          fontWeight: FontWeight.w600, fontSize: 14, height: 1.40),
      labelMedium: ui.labelMedium?.copyWith(
          fontWeight: FontWeight.w600, fontSize: 12, height: 1.40),
      labelSmall: ui.labelSmall?.copyWith(
          fontWeight: FontWeight.w700, fontSize: 11, height: 1.40),
    );
  }
}

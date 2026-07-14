// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';

import 'app_shapes.dart';
import 'signal_colors.dart';

/// ProtoCentral Design System v3 ("Signal Amber") → Material 3.
///
/// Source: /Users/akw/Downloads/ProtoCentral Design System (2).zip
///         references/colors_and_type.css
///
/// Fonts are bundled as assets (see `pubspec.yaml`) rather than fetched at
/// runtime, so the engine's font cache is populated from local TTF files —
/// this also keeps the app offline-capable and removes a known macOS engine
/// shutdown crash path triggered by dynamically-loaded fonts.
class AppTheme {
  AppTheme._();

  // === Brand (locked from logo) ===
  static const Color pcBrandBlue = Color(0xFF2C6E84);
  static const Color pcBrandBlueDk = Color(0xFF1F4E5E);
  static const Color pcBrandBlueLt = Color(0xFFC9DEE6);
  static const Color pcBrandGrey = Color(0xFF7A7E80);

  /// Dedicated dark surface for the navigation sidebar. Deeper and bluer than
  /// the content scaffold so the rail reads as its own brand-tinted zone.
  static const Color pcSidebarDark = Color(0xFF0A171C);

  // === Accent — Ember (dark orange) ===
  // Teal's complement on the wheel; the third brand colour alongside the teal
  // primary and the near-black surfaces. Used for selection, accent actions,
  // and "live" emphasis.
  static const Color pcAccent = Color(0xFFE8743B);
  static const Color pcAccentDk = Color(0xFFB5491A);
  static const Color pcAccentLt = Color(0xFFFFE0CC);
  static const Color pcAccentOn = Color(0xFF2A1303);

  // === Font family names — must match pubspec.yaml ===
  static const String fontDisplay = 'Saira';      // h1/h2, dashboard titles
  static const String fontUi = 'Jost';            // headlines/titles/labels
  static const String fontBody = 'Montserrat';    // paragraph + body
  static const String fontMono = 'JetBrainsMono'; // console, hex dumps

  static ThemeData light() => _build(_lightScheme, SignalColors.light);
  static ThemeData dark() => _build(_darkScheme, SignalColors.dark);

  static final ColorScheme _lightScheme = const ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF2C6E84),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFC9DEE6),
    onPrimaryContainer: Color(0xFF0A2933),
    secondary: Color(0xFFB5491A),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFFFE0CC),
    onSecondaryContainer: Color(0xFF3A1604),
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
    primary: Color(0xFF63B8D6),
    onPrimary: Color(0xFF00252F),
    primaryContainer: Color(0xFF184654),
    onPrimaryContainer: Color(0xFFBEE4F0),
    // Ember — dark orange accent (the third brand colour).
    secondary: Color(0xFFEC8A52),
    onSecondary: Color(0xFF3A1604),
    secondaryContainer: Color(0xFF5C2D12),
    onSecondaryContainer: Color(0xFFFFD7BC),
    tertiary: Color(0xFF8B93F8),
    onTertiary: Color(0xFF1E1B4B),
    tertiaryContainer: Color(0xFF332C9E),
    onTertiaryContainer: Color(0xFFE2E5FF),
    error: Color(0xFFF87171),
    onError: Color(0xFF450A0A),
    errorContainer: Color(0xFF5C1A17),
    onErrorContainer: Color(0xFFFFDAD6),
    // Content scaffold — deep teal-charcoal.
    surface: Color(0xFF0F181D),
    onSurface: Color(0xFFEAF1F4),
    // Elevation ladder: each step is a clearly perceptible lift so cards never
    // blend into the background. Cards default to `surfaceContainer`, the hero
    // and other raised panels to `surfaceContainerHigh`.
    surfaceContainerLowest: Color(0xFF0A1216),
    surfaceContainerLow: Color(0xFF152128),
    surfaceContainer: Color(0xFF1B2830),
    surfaceContainerHigh: Color(0xFF223440),
    surfaceContainerHighest: Color(0xFF2A3F4B),
    surfaceTint: Color(0xFF63B8D6),
    onSurfaceVariant: Color(0xFFAAB6BC),
    outline: Color(0xFF5E6D74),
    // Hairline used for card / control borders — bright enough to define an
    // edge against both the scaffold and the container surfaces.
    outlineVariant: Color(0xFF33424A),
    inverseSurface: Color(0xFFEAF1F4),
    onInverseSurface: Color(0xFF18242A),
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
      // Default font family for any widget that doesn't pick from textTheme.
      fontFamily: fontBody,
    );

    return base.copyWith(
      textTheme: _textTheme(scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontUi,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        // A mid-ladder container plus a hairline border so cards stay visually
        // separated from the scaffold on the dark theme (M3 elevation tint
        // alone is too subtle at these low luminances).
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.brMd,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: AppShapes.buttonShape,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: fontUi,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(
            fontFamily: fontUi,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: AppShapes.buttonShape,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(
            fontFamily: fontUi,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        // Distinct brand-tinted panel on dark; falls back to a low container
        // on light so the rail still separates from content.
        backgroundColor: scheme.brightness == Brightness.dark
            ? pcSidebarDark
            : scheme.surfaceContainerLow,
        // Ember accent for the active destination — the selected icon rides
        // an orange pill, its label picks up the same orange.
        selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          fontFamily: fontUi,
          color: scheme.secondary,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: fontUi,
          color: scheme.onSurfaceVariant,
        ),
        indicatorColor: scheme.secondaryContainer,
        useIndicator: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.brightness == Brightness.dark
            ? pcSidebarDark
            : scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.secondaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color:
                selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: fontUi,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? scheme.secondary : scheme.onSurfaceVariant,
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
        labelStyle: TextStyle(
          fontFamily: fontUi,
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

  /// Build a TextTheme that mixes the four bundled families per M3 role:
  ///   display* → Saira (700, all-caps friendly)
  ///   headline* / title* / label* → Jost (UI)
  ///   body* → Montserrat (paragraph)
  ///   (mono → JetBrainsMono is used inline via fontFamily in code/console widgets)
  static TextTheme _textTheme(ColorScheme scheme) {
    final onSurface = scheme.onSurface;
    return TextTheme(
      // Display — Saira 700
      displayLarge: TextStyle(
          fontFamily: fontDisplay,
          fontSize: 57,
          height: 1.05,
          fontWeight: FontWeight.w700,
          color: onSurface),
      displayMedium: TextStyle(
          fontFamily: fontDisplay,
          fontSize: 45,
          height: 1.08,
          fontWeight: FontWeight.w700,
          color: onSurface),
      displaySmall: TextStyle(
          fontFamily: fontDisplay,
          fontSize: 36,
          height: 1.10,
          fontWeight: FontWeight.w700,
          color: onSurface),
      // Headline — Jost 600
      headlineLarge: TextStyle(
          fontFamily: fontUi,
          fontSize: 32,
          height: 1.18,
          fontWeight: FontWeight.w600,
          color: onSurface),
      headlineMedium: TextStyle(
          fontFamily: fontUi,
          fontSize: 28,
          height: 1.22,
          fontWeight: FontWeight.w600,
          color: onSurface),
      headlineSmall: TextStyle(
          fontFamily: fontUi,
          fontSize: 24,
          height: 1.30,
          fontWeight: FontWeight.w600,
          color: onSurface),
      // Title — Jost 600
      titleLarge: TextStyle(
          fontFamily: fontUi,
          fontSize: 22,
          height: 1.30,
          fontWeight: FontWeight.w600,
          color: onSurface),
      titleMedium: TextStyle(
          fontFamily: fontUi,
          fontSize: 16,
          height: 1.40,
          fontWeight: FontWeight.w600,
          color: onSurface),
      titleSmall: TextStyle(
          fontFamily: fontUi,
          fontSize: 14,
          height: 1.40,
          fontWeight: FontWeight.w600,
          color: onSurface),
      // Body — Montserrat 400
      bodyLarge: TextStyle(
          fontFamily: fontBody,
          fontSize: 16,
          height: 1.55,
          fontWeight: FontWeight.w400,
          color: onSurface),
      bodyMedium: TextStyle(
          fontFamily: fontBody,
          fontSize: 14,
          height: 1.55,
          fontWeight: FontWeight.w400,
          color: onSurface),
      bodySmall: TextStyle(
          fontFamily: fontBody,
          fontSize: 12,
          height: 1.50,
          fontWeight: FontWeight.w400,
          color: onSurface),
      // Label — Jost 600/700
      labelLarge: TextStyle(
          fontFamily: fontUi,
          fontSize: 14,
          height: 1.40,
          fontWeight: FontWeight.w600,
          color: onSurface),
      labelMedium: TextStyle(
          fontFamily: fontUi,
          fontSize: 12,
          height: 1.40,
          fontWeight: FontWeight.w600,
          color: onSurface),
      labelSmall: TextStyle(
          fontFamily: fontUi,
          fontSize: 11,
          height: 1.40,
          fontWeight: FontWeight.w700,
          color: onSurface),
    );
  }
}

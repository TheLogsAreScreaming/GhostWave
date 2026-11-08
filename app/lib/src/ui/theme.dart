/// GhostWave look: brand colour tokens, the dark theme, and the type scale.
///
/// Every colour the app paints comes from here. Brand colours are from the
/// GhostWave brand guide; SOS and alerts deliberately use a plain high-contrast
/// red instead, so an emergency never looks like decoration.
library;

import 'package:flutter/material.dart';

/// Colour tokens. Primitives first (brand guide), then roles.
abstract final class GwColors {
  // Brand primitives (README_Brand_Guide.txt).
  /// Spectral Cyan.
  static const Color spectralCyan = Color(0xFF00E5F5);

  /// Phantom Violet.
  static const Color phantomViolet = Color(0xFF872BFF);

  /// Ghost Black: the app background.
  static const Color ghostBlack = Color(0xFF070B16);

  /// Mist White: body text.
  static const Color mistWhite = Color(0xFFF2F7FF);

  // Surfaces, stepped up from Ghost Black.
  /// Cards and sheets.
  static const Color surface1 = Color(0xFF0E1424);

  /// Raised containers (chat bubbles from others, banners).
  static const Color surface2 = Color(0xFF141C31);

  /// Highest containers.
  static const Color surface3 = Color(0xFF1B2540);

  /// Secondary text on surfaces (8.9:1 on Ghost Black).
  static const Color mutedText = Color(0xFFA9B4CC);

  /// Borders and disabled icons.
  static const Color outline = Color(0xFF5E6A85);

  /// Hairlines.
  static const Color outlineVariant = Color(0xFF29324A);

  /// Lighter violet for text and icons on dark (Phantom Violet itself is too
  /// dark for small text on Ghost Black).
  static const Color violetLight = Color(0xFFBF9BFF);

  // Status roles (not brand colours).
  /// Success: link up, delivered, ack received.
  static const Color success = Color(0xFF3DDC84);

  /// Alert red fill: SOS button, SOS banners, SOS map marker. White on it is
  /// 5.6:1. Not used for text on dark backgrounds (3.5:1); see [errorText].
  static const Color alert = Color(0xFFC62828);

  /// Text and icons on [alert].
  static const Color onAlert = Color(0xFFFFFFFF);

  /// Error and warning text and icons on dark surfaces (8.6:1 on Ghost Black).
  static const Color errorText = Color(0xFFFF8A80);

  /// Dark red container for warnings inside a page (key change, SOS active).
  static const Color alertContainer = Color(0xFF4A0D12);

  /// Text on [alertContainer].
  static const Color onAlertContainer = Color(0xFFFFDAD6);

  // Map markers sit on light OpenStreetMap tiles, so they use darker tones.
  /// Own node on the map.
  static const Color mapMe = Color(0xFF00838F);

  /// Contacts on the map.
  static const Color mapContact = Color(0xFF6A1BDB);

  /// Other heard nodes on the map.
  static const Color mapNearby = Color(0xFF546E7A);
}

/// Font families bundled under assets/fonts (all SIL OFL 1.1).
abstract final class GwFonts {
  /// Headlines.
  static const String headline = 'Space Grotesk';

  /// Body and UI text.
  static const String body = 'Inter';

  /// Node IDs, keys, addresses.
  static const String mono = 'JetBrains Mono';
}

/// Text styles that are not part of the Material type scale.
abstract final class GwText {
  /// Node IDs, keys and other technical values.
  static const TextStyle mono = TextStyle(fontFamily: GwFonts.mono, fontFeatures: [FontFeature.tabularFigures()]);
}

/// The app theme: dark only.
ThemeData buildGhostWaveTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: GwColors.spectralCyan,
    onPrimary: GwColors.ghostBlack,
    primaryContainer: Color(0xFF003A40),
    onPrimaryContainer: Color(0xFFA6F6FB),
    secondary: GwColors.phantomViolet,
    onSecondary: GwColors.mistWhite,
    secondaryContainer: Color(0xFF2D1563),
    onSecondaryContainer: Color(0xFFE6D8FF),
    tertiary: GwColors.violetLight,
    onTertiary: GwColors.ghostBlack,
    tertiaryContainer: Color(0xFF3A2470),
    onTertiaryContainer: Color(0xFFEBDFFF),
    error: GwColors.errorText,
    onError: GwColors.ghostBlack,
    errorContainer: GwColors.alertContainer,
    onErrorContainer: GwColors.onAlertContainer,
    surface: GwColors.ghostBlack,
    onSurface: GwColors.mistWhite,
    onSurfaceVariant: GwColors.mutedText,
    surfaceContainerLowest: Color(0xFF04070F),
    surfaceContainerLow: Color(0xFF0B101D),
    surfaceContainer: GwColors.surface1,
    surfaceContainerHigh: GwColors.surface2,
    surfaceContainerHighest: GwColors.surface3,
    outline: GwColors.outline,
    outlineVariant: GwColors.outlineVariant,
    inverseSurface: GwColors.mistWhite,
    onInverseSurface: GwColors.ghostBlack,
    inversePrimary: Color(0xFF00696F),
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: GwColors.spectralCyan,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: GwFonts.body);
  final t = base.textTheme;
  TextStyle? head(TextStyle? s, FontWeight w) => s?.copyWith(fontFamily: GwFonts.headline, fontWeight: w);
  final text = t.copyWith(
    displayLarge: head(t.displayLarge, FontWeight.w700),
    displayMedium: head(t.displayMedium, FontWeight.w700),
    displaySmall: head(t.displaySmall, FontWeight.w700),
    headlineLarge: head(t.headlineLarge, FontWeight.w700),
    headlineMedium: head(t.headlineMedium, FontWeight.w700),
    headlineSmall: head(t.headlineSmall, FontWeight.w500),
    titleLarge: head(t.titleLarge, FontWeight.w500),
  );

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: GwColors.ghostBlack,
    appBarTheme: AppBarTheme(
      backgroundColor: GwColors.ghostBlack,
      foregroundColor: GwColors.mistWhite,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.titleLarge?.copyWith(color: GwColors.mistWhite),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: GwColors.surface1,
      indicatorColor: Color(0xFF003A40),
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: const CardThemeData(color: GwColors.surface1, surfaceTintColor: Colors.transparent),
    dividerTheme: const DividerThemeData(color: GwColors.outlineVariant),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: GwColors.surface3,
      contentTextStyle: TextStyle(color: GwColors.mistWhite, fontFamily: GwFonts.body),
    ),
  );
}

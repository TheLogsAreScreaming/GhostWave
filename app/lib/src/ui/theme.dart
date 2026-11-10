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

/// Spacing steps (logical px). Layout uses these, not ad-hoc numbers.
abstract final class GwSpace {
  /// Hairline gaps.
  static const double xs = 4;

  /// Between related items.
  static const double sm = 8;

  /// Default inner padding.
  static const double md = 12;

  /// Page gutters.
  static const double lg = 16;

  /// Between sections.
  static const double xl = 24;
}

/// Corner radii.
abstract final class GwRadius {
  /// Chips, small controls.
  static const double sm = 10;

  /// Inputs, tiles.
  static const double md = 14;

  /// Cards, bubbles, sheets.
  static const double lg = 20;

  /// Fully rounded pills.
  static const double pill = 999;
}

/// Window size classes (Material 3), the only breakpoints the app uses.
enum WindowSizeClass {
  /// Phones in portrait, under 600.
  compact,

  /// Small tablets, foldables, 600 to 840.
  medium,

  /// Tablets and small desktop windows, 840 to 1200.
  expanded,

  /// Desktop windows, 1200 and up.
  large;

  /// The class for a window [width] in logical px.
  static WindowSizeClass of(double width) => switch (width) {
    < 600 => compact,
    < 840 => medium,
    < 1200 => expanded,
    _ => large,
  };
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
    headlineSmall: head(t.headlineSmall, FontWeight.w700),
    titleLarge: head(t.titleLarge, FontWeight.w700)?.copyWith(fontSize: 24, letterSpacing: -0.2),
    titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );
  const pill = StadiumBorder();
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(GwRadius.md));

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: GwColors.ghostBlack,
    appBarTheme: AppBarTheme(
      backgroundColor: GwColors.ghostBlack,
      foregroundColor: GwColors.mistWhite,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.titleLarge?.copyWith(color: GwColors.mistWhite),
      titleSpacing: GwSpace.lg + GwSpace.xs,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: GwColors.surface1,
      indicatorColor: GwColors.spectralCyan.withValues(alpha: 0.16),
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelMedium?.copyWith(
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? GwColors.mistWhite : GwColors.mutedText,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? GwColors.spectralCyan : GwColors.mutedText),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: GwColors.surface1,
      indicatorColor: GwColors.spectralCyan.withValues(alpha: 0.16),
      selectedIconTheme: const IconThemeData(color: GwColors.spectralCyan),
      unselectedIconTheme: const IconThemeData(color: GwColors.mutedText),
      selectedLabelTextStyle: text.labelLarge?.copyWith(color: GwColors.mistWhite, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: text.labelLarge?.copyWith(color: GwColors.mutedText),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(color: GwColors.surface3, borderRadius: BorderRadius.circular(GwRadius.pill)),
      labelColor: GwColors.mistWhite,
      unselectedLabelColor: GwColors.mutedText,
      labelStyle: text.labelLarge,
      unselectedLabelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      splashBorderRadius: BorderRadius.circular(GwRadius.pill),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: GwSpace.lg, vertical: GwSpace.xs),
      minVerticalPadding: GwSpace.sm,
      horizontalTitleGap: GwSpace.md,
      titleTextStyle: text.titleMedium?.copyWith(color: GwColors.mistWhite),
      subtitleTextStyle: text.bodyMedium?.copyWith(color: GwColors.mutedText),
      iconColor: GwColors.mutedText,
      shape: rounded,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: GwColors.spectralCyan,
      foregroundColor: GwColors.ghostBlack,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      extendedTextStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      shape: pill,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 48), shape: pill, textStyle: text.labelLarge),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: pill,
        side: const BorderSide(color: GwColors.outline),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 44), shape: pill, textStyle: text.labelLarge),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GwColors.surface2,
      contentPadding: const EdgeInsets.symmetric(horizontal: GwSpace.lg, vertical: GwSpace.md + 2),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(GwRadius.md), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GwRadius.md),
        borderSide: const BorderSide(color: GwColors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GwRadius.md),
        borderSide: const BorderSide(color: GwColors.spectralCyan, width: 1.5),
      ),
      hintStyle: text.bodyLarge?.copyWith(color: GwColors.mutedText),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: GwColors.surface2,
      side: const BorderSide(color: GwColors.outlineVariant),
      shape: pill,
      labelStyle: text.labelLarge?.copyWith(color: GwColors.mistWhite),
    ),
    badgeTheme: const BadgeThemeData(backgroundColor: GwColors.spectralCyan, textColor: GwColors.ghostBlack),
    cardTheme: CardThemeData(
      color: GwColors.surface1,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GwRadius.lg),
        side: const BorderSide(color: GwColors.outlineVariant),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: GwColors.surface1,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(GwRadius.lg))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: GwColors.surface1,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GwRadius.lg)),
    ),
    dividerTheme: const DividerThemeData(color: GwColors.outlineVariant, space: 1),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: GwColors.surface3,
      contentTextStyle: TextStyle(color: GwColors.mistWhite, fontFamily: GwFonts.body),
    ),
  );
}

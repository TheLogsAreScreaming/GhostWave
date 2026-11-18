/// GhostWave look: brand colour tokens, the dark theme, and the type scale.
///
/// Every colour the app paints comes from here. Brand colours are from the
/// GhostWave brand guide; SOS and alerts deliberately use a plain high-contrast
/// red instead, so an emergency never looks like decoration.
library;

import 'package:flutter/material.dart';

import 'page_backdrop.dart';
import 'palettes.dart';

export 'palettes.dart';

/// Colour roles for the active theme. Screens read these; [use] switches
/// them when the user changes the theme, and the app root then rebuilds every
/// widget. Map marker colours are fixed: they sit on light map tiles.
abstract final class GwColors {
  static GwPalette _p = GwPalette.stock;
  static bool _glass = false;

  /// The active palette.
  static GwPalette get palette => _p;

  /// Whether pages are see-through over a gradient or photo background.
  static bool get glass => _glass;

  /// Makes [palette] the active one; [glass] when the background shows
  /// through. Called by the app root before it builds.
  static void use(GwPalette palette, {bool glass = false}) {
    _p = palette;
    _glass = glass;
  }

  /// Main accent (Spectral Cyan in the stock theme).
  static Color get accent => _p.accent;

  /// Second colour (Phantom Violet in the stock theme).
  static Color get secondary => _p.secondary;

  /// Page background (Ghost Black in the stock theme).
  static Color get background => _p.background;

  /// Body text (Mist White in the stock theme).
  static Color get text => _p.text;

  /// Cards and sheets.
  static Color get surface1 => _p.surface1;

  /// Card fill: [surface1], frosted when the background shows through.
  static Color get card => _glass ? _p.surface1.withValues(alpha: kGlassCardAlpha) : _p.surface1;

  /// Raised containers (chat bubbles from others, banners).
  static Color get surface2 => _p.surface2;

  /// Highest containers.
  static Color get surface3 => _p.surface3;

  /// Secondary text on surfaces.
  static Color get mutedText => _p.mutedText;

  /// Borders and disabled icons.
  static Color get outline => _p.outline;

  /// Hairlines.
  static Color get outlineVariant => _p.outlineVariant;

  /// Lighter third colour for text and icons on dark.
  static Color get tertiary => _p.tertiary;

  /// Success: link up, delivered, ack received.
  static Color get success => _p.success;

  /// Alert fill: SOS button, banners and map marker; not for text on dark (see [errorText]).
  static Color get alert => _p.alert;

  /// Text and icons on [alert].
  static Color get onAlert => _p.onAlert;

  /// Error and warning text and icons on dark surfaces.
  static Color get errorText => _p.errorText;

  /// Container for warnings inside a page (key change, SOS active).
  static Color get alertContainer => _p.alertContainer;

  /// Text on [alertContainer].
  static Color get onAlertContainer => _p.onAlertContainer;

  /// Own node on the map.
  static const Color mapMe = Color(0xFF00838F);

  /// Contacts on the map.
  static const Color mapContact = Color(0xFF6A1BDB);

  /// Other heard nodes on the map.
  static const Color mapNearby = Color(0xFF546E7A);

  /// Traffic map: adverts (beacons, identities).
  static const Color trafficAdvert = Color(0xFFFF5FA2);

  /// Traffic map: direct messages.
  static const Color trafficDirect = Color(0xFF4C8DFF);

  /// Traffic map: channel messages.
  static const Color trafficChannel = Color(0xFF3DDC84);

  /// Traffic map: receipts and acknowledgements.
  static const Color trafficAck = Color(0xFF22D3EE);

  /// Traffic map: traceroutes.
  static const Color trafficTrace = Color(0xFFFF9F1C);

  /// Traffic map: everything else.
  static const Color trafficOther = Color(0xFFB07CFF);

  /// Traffic map: the ring around a node heard in the last few minutes.
  static const Color trafficHeard = Color(0xFF3DDC84);
}

/// How opaque frosted cards are over a gradient or photo background. High
/// enough that text on a card keeps its contrast over any photo.
const double kGlassCardAlpha = 0.72;

/// How opaque the navigation bar and rail are over a background.
const double kGlassBarAlpha = 0.80;

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

/// The app theme for [p] (dark only). With [glass], pages are see-through so
/// a gradient or photo background shows, and cards and bars are frosted.
ThemeData buildGhostWaveTheme([GwPalette p = GwPalette.stock, bool glass = false]) {
  final scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: p.accent,
    onPrimary: p.onAccent,
    primaryContainer: p.accentContainer,
    onPrimaryContainer: p.onAccentContainer,
    secondary: p.secondary,
    onSecondary: p.onSecondary,
    secondaryContainer: p.secondaryContainer,
    onSecondaryContainer: p.onSecondaryContainer,
    tertiary: p.tertiary,
    onTertiary: p.onTertiary,
    tertiaryContainer: p.tertiaryContainer,
    onTertiaryContainer: p.onTertiaryContainer,
    error: p.errorText,
    onError: p.background,
    errorContainer: p.alertContainer,
    onErrorContainer: p.onAlertContainer,
    surface: p.background,
    onSurface: p.text,
    onSurfaceVariant: p.mutedText,
    surfaceContainerLowest: p.surfaceLowest,
    surfaceContainerLow: p.surfaceLow,
    surfaceContainer: p.surface1,
    surfaceContainerHigh: p.surface2,
    surfaceContainerHighest: p.surface3,
    outline: p.outline,
    outlineVariant: p.outlineVariant,
    inverseSurface: p.text,
    onInverseSurface: p.background,
    inversePrimary: p.inverseAccent,
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: p.accent,
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
    titleLarge: head(t.titleLarge, FontWeight.w700)?.copyWith(fontSize: 24, letterSpacing: -0.5),
    titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
  );
  final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(GwRadius.md));
  // glass: pages are clear so the background shows; bars and cards are frosted
  final page = glass ? Colors.transparent : p.background;
  final bar = glass ? p.surface1.withValues(alpha: kGlassBarAlpha) : p.surface1;
  final card = glass ? p.surface1.withValues(alpha: kGlassCardAlpha) : p.surface1;
  final cardEdge = glass ? p.text.withValues(alpha: 0.16) : p.outlineVariant;
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(GwRadius.md));

  return base.copyWith(
    textTheme: text,
    pageTransitionsTheme: glass ? backdropPageTransitions() : null,
    scaffoldBackgroundColor: page,
    appBarTheme: AppBarTheme(
      backgroundColor: page,
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.titleLarge?.copyWith(color: p.text),
      titleSpacing: GwSpace.lg + GwSpace.xs,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: bar,
      indicatorColor: p.accent.withValues(alpha: 0.23),
      surfaceTintColor: Colors.transparent,
      height: 76,
      indicatorShape: rounded,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelMedium?.copyWith(
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? p.text : p.mutedText,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.accent : p.mutedText),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: bar,
      indicatorColor: p.accent.withValues(alpha: 0.16),
      selectedIconTheme: IconThemeData(color: p.accent),
      unselectedIconTheme: IconThemeData(color: p.mutedText),
      selectedLabelTextStyle: text.labelLarge?.copyWith(color: p.text, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: text.labelLarge?.copyWith(color: p.mutedText),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(color: p.surface3, borderRadius: BorderRadius.circular(GwRadius.pill)),
      labelColor: p.text,
      unselectedLabelColor: p.mutedText,
      labelStyle: text.labelLarge,
      unselectedLabelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      splashBorderRadius: BorderRadius.circular(GwRadius.pill),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: GwSpace.lg, vertical: GwSpace.xs),
      minVerticalPadding: GwSpace.xs,
      horizontalTitleGap: GwSpace.md,
      titleTextStyle: text.titleMedium?.copyWith(color: p.text),
      subtitleTextStyle: text.bodyMedium?.copyWith(color: p.mutedText),
      iconColor: p.mutedText,
      shape: rounded,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.accent,
      foregroundColor: p.onAccent,
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
        side: BorderSide(color: p.outline),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 44), shape: pill, textStyle: text.labelLarge),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface2,
      contentPadding: const EdgeInsets.symmetric(horizontal: GwSpace.lg, vertical: GwSpace.md + 2),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(GwRadius.md), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GwRadius.md),
        borderSide: BorderSide(color: p.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GwRadius.md),
        borderSide: BorderSide(color: p.accent, width: 1.5),
      ),
      hintStyle: text.bodyLarge?.copyWith(color: p.mutedText),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface2,
      side: BorderSide(color: p.outlineVariant),
      shape: pill,
      labelStyle: text.labelLarge?.copyWith(color: p.text),
    ),
    badgeTheme: BadgeThemeData(backgroundColor: p.accent, textColor: p.onAccent),
    cardTheme: CardThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GwRadius.lg),
        side: BorderSide(color: cardEdge),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface1,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(GwRadius.lg))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface1,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GwRadius.lg)),
    ),
    dividerTheme: DividerThemeData(color: p.outlineVariant, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.surface3,
      contentTextStyle: TextStyle(color: p.text, fontFamily: GwFonts.body),
    ),
  );
}

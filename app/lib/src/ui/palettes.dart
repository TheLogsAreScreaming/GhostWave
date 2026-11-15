/// The app's colour themes: Stock (the GhostWave brand look), Season (changes
/// with the time of year), Colour-blind safe, and Night (red only, dim, to keep
/// dark-adapted eyes). Each is a [GwPalette]; [GwColors] reads the active one.
library;

import 'package:flutter/material.dart';

/// Which colour theme the user picked.
enum LookTheme {
  /// The GhostWave brand colours.
  stock,

  /// Colours for the current season (northern hemisphere).
  seasonal,

  /// Blue, yellow and orange that stay apart with every common colour-vision
  /// difference; no meaning rests on red against green.
  colorBlind,

  /// Red only and dim, to keep night vision.
  night;

  /// Name shown in settings.
  String get label => switch (this) {
    stock => 'Stock',
    seasonal => 'Season',
    colorBlind => 'Colour-blind safe',
    night => 'Night vision',
  };
}

/// Meteorological seasons, northern hemisphere.
enum Season {
  /// December to February.
  winter,

  /// March to May.
  spring,

  /// June to August.
  summer,

  /// September to November.
  autumn;

  /// The season on [date] (northern hemisphere, by month).
  static Season of(DateTime date) => switch (date.month) {
    12 || 1 || 2 => winter,
    3 || 4 || 5 => spring,
    6 || 7 || 8 => summer,
    _ => autumn,
  };

  /// Name shown in settings.
  String get label => switch (this) {
    winter => 'Winter',
    spring => 'Spring',
    summer => 'Summer',
    autumn => 'Autumn',
  };
}

/// Every colour role the app paints. Map markers are not here: they sit on
/// light map tiles and keep their own fixed tones.
@immutable
class GwPalette {
  /// Creates a palette.
  const GwPalette({
    required this.name,
    required this.accent,
    required this.onAccent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.background,
    required this.text,
    required this.surfaceLowest,
    required this.surfaceLow,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.mutedText,
    required this.outline,
    required this.outlineVariant,
    required this.inverseAccent,
    required this.success,
    required this.alert,
    required this.onAlert,
    required this.errorText,
    required this.alertContainer,
    required this.onAlertContainer,
    required this.gradient,
  });

  /// Short name, for tests and logs.
  final String name;

  /// Main accent: buttons, selection, links.
  final Color accent;

  /// Text and icons on [accent].
  final Color onAccent;

  /// Container tinted with the accent.
  final Color accentContainer;

  /// Text on [accentContainer].
  final Color onAccentContainer;

  /// Second brand colour.
  final Color secondary;

  /// Text on [secondary].
  final Color onSecondary;

  /// Container tinted with the secondary colour.
  final Color secondaryContainer;

  /// Text on [secondaryContainer].
  final Color onSecondaryContainer;

  /// Third colour, light enough for text and icons on dark.
  final Color tertiary;

  /// Text on [tertiary].
  final Color onTertiary;

  /// Container tinted with the tertiary colour.
  final Color tertiaryContainer;

  /// Text on [tertiaryContainer].
  final Color onTertiaryContainer;

  /// Page background.
  final Color background;

  /// Body text.
  final Color text;

  /// Darkest surface.
  final Color surfaceLowest;

  /// Just above the background.
  final Color surfaceLow;

  /// Cards and sheets.
  final Color surface1;

  /// Raised containers.
  final Color surface2;

  /// Highest containers.
  final Color surface3;

  /// Secondary text.
  final Color mutedText;

  /// Borders and disabled icons.
  final Color outline;

  /// Hairlines.
  final Color outlineVariant;

  /// The accent as used on a light surface.
  final Color inverseAccent;

  /// Success: link up, delivered, ack received.
  final Color success;

  /// Alert fill: SOS button, banners and marker.
  final Color alert;

  /// Text and icons on [alert].
  final Color onAlert;

  /// Error and warning text on dark surfaces.
  final Color errorText;

  /// Container for warnings inside a page.
  final Color alertContainer;

  /// Text on [alertContainer].
  final Color onAlertContainer;

  /// Three stops for the gradient background, top-left to bottom-right.
  final List<Color> gradient;

  /// Whether the whole screen is pushed through the red-only night filter.
  bool get redOnly => identical(this, night);

  /// The palette for [theme] on [date].
  static GwPalette forTheme(LookTheme theme, DateTime date) => switch (theme) {
    LookTheme.stock => stock,
    LookTheme.seasonal => forSeason(Season.of(date)),
    LookTheme.colorBlind => colorBlind,
    LookTheme.night => night,
  };

  /// The palette for [season].
  static GwPalette forSeason(Season season) => switch (season) {
    Season.winter => winter,
    Season.spring => spring,
    Season.summer => summer,
    Season.autumn => autumn,
  };

  /// The GhostWave brand look (brand guide colours).
  static const stock = GwPalette(
    name: 'stock',
    accent: Color(0xFF55F1D8), // Spectral Cyan
    onAccent: Color(0xFF090D19),
    accentContainer: Color(0xFF003A40),
    onAccentContainer: Color(0xFFA6F6FB),
    secondary: Color(0xFF872BFF), // Phantom Violet
    onSecondary: Color(0xFFF2F7FF),
    secondaryContainer: Color(0xFF2D1563),
    onSecondaryContainer: Color(0xFFE6D8FF),
    tertiary: Color(0xFFBF9BFF),
    onTertiary: Color(0xFF090D19),
    tertiaryContainer: Color(0xFF3A2470),
    onTertiaryContainer: Color(0xFFEBDFFF),
    background: Color(0xFF090D19), // Ghost Black
    text: Color(0xFFF2F7FF), // Mist White
    surfaceLowest: Color(0xFF04070F),
    surfaceLow: Color(0xFF0B101D),
    surface1: Color(0xFF11192B),
    surface2: Color(0xFF182440),
    surface3: Color(0xFF233359),
    mutedText: Color(0xFFA9B4CC),
    outline: Color(0xFF5E6A85),
    outlineVariant: Color(0xFF34446A),
    inverseAccent: Color(0xFF00696F),
    success: Color(0xFF3DDC84),
    alert: Color(0xFFC62828),
    onAlert: Color(0xFFFFFFFF),
    errorText: Color(0xFFFF8A80),
    alertContainer: Color(0xFF4A0D12),
    onAlertContainer: Color(0xFFFFDAD6),
    gradient: [Color(0xFF0E2E3A), Color(0xFF090D19), Color(0xFF2A1458)],
  );

  /// Winter: ice blue and periwinkle on deep navy.
  static const winter = GwPalette(
    name: 'winter',
    accent: Color(0xFF8FD3FF),
    onAccent: Color(0xFF071521),
    accentContainer: Color(0xFF0D3350),
    onAccentContainer: Color(0xFFCDEBFF),
    secondary: Color(0xFF4F6BE8),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFF1E2B66),
    onSecondaryContainer: Color(0xFFDDE3FF),
    tertiary: Color(0xFFC3D0FF),
    onTertiary: Color(0xFF071521),
    tertiaryContainer: Color(0xFF2A3666),
    onTertiaryContainer: Color(0xFFE3E9FF),
    background: Color(0xFF070C16),
    text: Color(0xFFF1F6FF),
    surfaceLowest: Color(0xFF03060C),
    surfaceLow: Color(0xFF0B111D),
    surface1: Color(0xFF101827),
    surface2: Color(0xFF172235),
    surface3: Color(0xFF213049),
    mutedText: Color(0xFFA9B6CB),
    outline: Color(0xFF5C6B84),
    outlineVariant: Color(0xFF2E3D57),
    inverseAccent: Color(0xFF00629A),
    success: Color(0xFF3DDC84),
    alert: Color(0xFFC62828),
    onAlert: Color(0xFFFFFFFF),
    errorText: Color(0xFFFF8A80),
    alertContainer: Color(0xFF4A0D12),
    onAlertContainer: Color(0xFFFFDAD6),
    gradient: [Color(0xFF15305A), Color(0xFF070C16), Color(0xFF2E3B6E)],
  );

  /// Spring: new-leaf green and blossom pink.
  static const spring = GwPalette(
    name: 'spring',
    accent: Color(0xFF86E38A),
    onAccent: Color(0xFF06140A),
    accentContainer: Color(0xFF173F1E),
    onAccentContainer: Color(0xFFCDF5CF),
    secondary: Color(0xFFFF8FB8),
    onSecondary: Color(0xFF2A0715),
    secondaryContainer: Color(0xFF4F1A30),
    onSecondaryContainer: Color(0xFFFFD9E6),
    tertiary: Color(0xFFF7C6DA),
    onTertiary: Color(0xFF2A0715),
    tertiaryContainer: Color(0xFF4A2535),
    onTertiaryContainer: Color(0xFFFFE3EE),
    background: Color(0xFF08110C),
    text: Color(0xFFF2FAF3),
    surfaceLowest: Color(0xFF040A06),
    surfaceLow: Color(0xFF0C1610),
    surface1: Color(0xFF101C15),
    surface2: Color(0xFF17271D),
    surface3: Color(0xFF213628),
    mutedText: Color(0xFFAAC2B0),
    outline: Color(0xFF5E7565),
    outlineVariant: Color(0xFF2E4436),
    inverseAccent: Color(0xFF1F6E2A),
    success: Color(0xFF3DDC84),
    alert: Color(0xFFC62828),
    onAlert: Color(0xFFFFFFFF),
    errorText: Color(0xFFFF8A80),
    alertContainer: Color(0xFF4A0D12),
    onAlertContainer: Color(0xFFFFDAD6),
    gradient: [Color(0xFF184426), Color(0xFF08110C), Color(0xFF45203A)],
  );

  /// Summer: sun gold and coral over deep teal.
  static const summer = GwPalette(
    name: 'summer',
    accent: Color(0xFFFFD166),
    onAccent: Color(0xFF1A1200),
    accentContainer: Color(0xFF4A3A0A),
    onAccentContainer: Color(0xFFFFEBB8),
    secondary: Color(0xFFFF7F50),
    onSecondary: Color(0xFF200800),
    secondaryContainer: Color(0xFF55220F),
    onSecondaryContainer: Color(0xFFFFDBCC),
    tertiary: Color(0xFF7FDBDA),
    onTertiary: Color(0xFF041414),
    tertiaryContainer: Color(0xFF134645),
    onTertiaryContainer: Color(0xFFCFF5F4),
    background: Color(0xFF071313),
    text: Color(0xFFF2FBFA),
    surfaceLowest: Color(0xFF030A0A),
    surfaceLow: Color(0xFF0B1818),
    surface1: Color(0xFF0F1F1F),
    surface2: Color(0xFF152C2C),
    surface3: Color(0xFF1E3B3B),
    mutedText: Color(0xFFA8C3C1),
    outline: Color(0xFF5B7775),
    outlineVariant: Color(0xFF2A4443),
    inverseAccent: Color(0xFF7A5800),
    success: Color(0xFF3DDC84),
    alert: Color(0xFFC62828),
    onAlert: Color(0xFFFFFFFF),
    errorText: Color(0xFFFF8A80),
    alertContainer: Color(0xFF4A0D12),
    onAlertContainer: Color(0xFFFFDAD6),
    gradient: [Color(0xFF0F4241), Color(0xFF071313), Color(0xFF4A3210)],
  );

  /// Autumn: amber and rust on dark walnut.
  static const autumn = GwPalette(
    name: 'autumn',
    accent: Color(0xFFFFB259),
    onAccent: Color(0xFF1C0E00),
    accentContainer: Color(0xFF4D2E08),
    onAccentContainer: Color(0xFFFFDDB5),
    secondary: Color(0xFFB5462F),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFF4E1C12),
    onSecondaryContainer: Color(0xFFFFDAD2),
    tertiary: Color(0xFFE8C07A),
    onTertiary: Color(0xFF1C0E00),
    tertiaryContainer: Color(0xFF4A3613),
    onTertiaryContainer: Color(0xFFFCE6BF),
    background: Color(0xFF120B07),
    text: Color(0xFFFCF4EC),
    surfaceLowest: Color(0xFF0A0603),
    surfaceLow: Color(0xFF180F09),
    surface1: Color(0xFF1E140D),
    surface2: Color(0xFF2A1C12),
    surface3: Color(0xFF3A2819),
    mutedText: Color(0xFFC6B4A2),
    outline: Color(0xFF7A6553),
    outlineVariant: Color(0xFF43311F),
    inverseAccent: Color(0xFF8A4F00),
    success: Color(0xFF3DDC84),
    alert: Color(0xFFC62828),
    onAlert: Color(0xFFFFFFFF),
    errorText: Color(0xFFFF8A80),
    alertContainer: Color(0xFF4A0D12),
    onAlertContainer: Color(0xFFFFDAD6),
    gradient: [Color(0xFF45220C), Color(0xFF120B07), Color(0xFF3A2C10)],
  );

  /// Colour-blind safe (Okabe-Ito hues): yellow accent, blue for success,
  /// orange for errors and SOS. Every state also keeps its icon and word.
  static const colorBlind = GwPalette(
    name: 'colorBlind',
    accent: Color(0xFFF0E442),
    onAccent: Color(0xFF14130A),
    accentContainer: Color(0xFF45410E),
    onAccentContainer: Color(0xFFFBF5B8),
    secondary: Color(0xFF0072B2),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFF0B3550),
    onSecondaryContainer: Color(0xFFCFE8FA),
    tertiary: Color(0xFF8FCBF2),
    onTertiary: Color(0xFF04121C),
    tertiaryContainer: Color(0xFF15405E),
    onTertiaryContainer: Color(0xFFD8EEFC),
    background: Color(0xFF0B0B0F),
    text: Color(0xFFF5F5F7),
    surfaceLowest: Color(0xFF050507),
    surfaceLow: Color(0xFF111116),
    surface1: Color(0xFF16161D),
    surface2: Color(0xFF202029),
    surface3: Color(0xFF2C2C38),
    mutedText: Color(0xFFBBBBCB),
    outline: Color(0xFF6E6E80),
    outlineVariant: Color(0xFF3A3A48),
    inverseAccent: Color(0xFF6B6400),
    success: Color(0xFF56B4E9),
    alert: Color(0xFFA94300),
    onAlert: Color(0xFFFFFFFF),
    errorText: Color(0xFFFFA24D),
    alertContainer: Color(0xFF3D1A00),
    onAlertContainer: Color(0xFFFFDCC2),
    gradient: [Color(0xFF0B2E45), Color(0xFF0B0B0F), Color(0xFF3A3510)],
  );

  /// Night vision: dim red on black. The app also passes the whole screen,
  /// maps and photos included, through a red-only filter in this theme.
  static const night = GwPalette(
    name: 'night',
    accent: Color(0xFFFF4A3D),
    onAccent: Color(0xFF000000),
    accentContainer: Color(0xFF3A0905),
    onAccentContainer: Color(0xFFFF8F85),
    secondary: Color(0xFFB3261E),
    onSecondary: Color(0xFF000000),
    secondaryContainer: Color(0xFF2C0704),
    onSecondaryContainer: Color(0xFFFF8F85),
    tertiary: Color(0xFFFF7A6E),
    onTertiary: Color(0xFF000000),
    tertiaryContainer: Color(0xFF330806),
    onTertiaryContainer: Color(0xFFFF9C93),
    background: Color(0xFF000000),
    text: Color(0xFFFF6B5E),
    surfaceLowest: Color(0xFF000000),
    surfaceLow: Color(0xFF080000),
    surface1: Color(0xFF120202),
    surface2: Color(0xFF1C0404),
    surface3: Color(0xFF280707),
    mutedText: Color(0xFFD9473B),
    outline: Color(0xFF7A1A13),
    outlineVariant: Color(0xFF3D0B08),
    inverseAccent: Color(0xFF7A1A13),
    success: Color(0xFFFF8F85),
    alert: Color(0xFFFF2D20),
    onAlert: Color(0xFF000000),
    errorText: Color(0xFFFF8A7F),
    alertContainer: Color(0xFF3A0905),
    onAlertContainer: Color(0xFFFFA59D),
    gradient: [Color(0xFF1A0202), Color(0xFF000000), Color(0xFF120101)],
  );

  /// Every palette, for tests and previews.
  static const all = [stock, winter, spring, summer, autumn, colorBlind, night];
}

/// Colour matrix for Night vision: green and blue light are folded into the
/// red channel and then dropped, so nothing on screen emits anything but red.
/// Red itself passes at full strength, so the theme's red text keeps its
/// contrast; maps, photos and node marks come out in shades of red.
const List<double> kNightVisionMatrix = [
  0.8, 0.5, 0.25, 0, 0, //
  0, 0, 0, 0, 0, //
  0, 0, 0, 0, 0, //
  0, 0, 0, 1, 0, //
];

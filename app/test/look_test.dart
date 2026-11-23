// Look: the four colour themes (contrast in each), the season by date, the
// night-vision filter, the saved theme and background, background and node
// photos (picked, replaced, removed), node colours, and the screens.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/look.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/ui/look_screen.dart';
import 'package:ghostwave_app/src/ui/node_mark.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WCAG contrast ratio of two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [top] at [alpha] over opaque [under].
Color over(Color top, double alpha, Color under) => Color.alphaBlend(top.withValues(alpha: alpha), under);

class FakePhotos implements LookPhotos {
  final List<String> picked = [];
  final List<String> removed = [];
  bool cancel = false;

  @override
  Future<String?> pick(String name, {required double maxSide}) async {
    if (cancel) return null;
    final path = '/look/$name-${picked.length}.jpg';
    picked.add(path);
    return path;
  }

  @override
  Future<void> remove(String path) async => removed.add(path);
}

Future<ProviderContainer> container(Map<String, Object> prefs, {FakePhotos? photos, DateTime? today}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(p),
      lookPhotosProvider.overrideWithValue(photos ?? FakePhotos()),
      lookClockProvider.overrideWithValue(() => today ?? DateTime(2026, 11, 14)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  tearDown(() => GwColors.use(GwPalette.stock));

  group('seasons', () {
    test('by month, northern hemisphere', () {
      expect(
        [for (var m = 1; m <= 12; m++) Season.of(DateTime(2026, m, 15))],
        [
          Season.winter,
          Season.winter,
          Season.spring,
          Season.spring,
          Season.spring,
          Season.summer,
          Season.summer,
          Season.summer,
          Season.autumn,
          Season.autumn,
          Season.autumn,
          Season.winter,
        ],
      );
    });

    test('the Season theme follows the date', () {
      expect(GwPalette.forTheme(LookTheme.seasonal, DateTime(2026, 11, 14)), same(GwPalette.autumn));
      expect(GwPalette.forTheme(LookTheme.seasonal, DateTime(2027, 1, 2)), same(GwPalette.winter));
      expect(GwPalette.forTheme(LookTheme.seasonal, DateTime(2027, 4, 2)), same(GwPalette.spring));
      expect(GwPalette.forTheme(LookTheme.seasonal, DateTime(2027, 7, 2)), same(GwPalette.summer));
      expect(GwPalette.forTheme(LookTheme.stock, DateTime(2027, 7, 2)), same(GwPalette.stock));
    });
  });

  group('every palette is readable', () {
    for (final p in GwPalette.all) {
      test(p.name, () {
        // body and secondary text on every surface they sit on
        for (final bg in [p.background, p.surface1, p.surface2]) {
          expect(contrast(p.text, bg), greaterThanOrEqualTo(4.5), reason: 'text');
          expect(contrast(p.mutedText, bg), greaterThanOrEqualTo(3.0), reason: 'muted text');
        }
        expect(contrast(p.mutedText, p.background), greaterThanOrEqualTo(4.5), reason: 'muted text on page');
        expect(contrast(p.onAccent, p.accent), greaterThanOrEqualTo(4.5), reason: 'on accent');
        expect(contrast(p.onAlert, p.alert), greaterThanOrEqualTo(4.5), reason: 'on SOS red');
        expect(contrast(p.errorText, p.background), greaterThanOrEqualTo(4.5), reason: 'error text');
        expect(contrast(p.onAlertContainer, p.alertContainer), greaterThanOrEqualTo(4.5), reason: 'warning box');
        expect(contrast(p.accent, p.background), greaterThanOrEqualTo(3.0), reason: 'accent icons');
        expect(contrast(p.success, p.background), greaterThanOrEqualTo(3.0), reason: 'success icons');
        expect(p.gradient, hasLength(3));
      });

      // Night vision never shows a gradient or photo
      if (!p.redOnly) {
        test('${p.name}: frosted cards stay readable over any photo', () {
          // worst cases: a white or a black photo under the scrim
          for (final photo in [Colors.white, Colors.black]) {
            final page = over(p.background, 0.6, photo);
            final card = over(p.surface1, kGlassCardAlpha, page);
            expect(contrast(p.text, card), greaterThanOrEqualTo(4.5), reason: 'text on card over $photo');
            expect(contrast(p.mutedText, card), greaterThanOrEqualTo(3.0), reason: 'muted on card over $photo');
            expect(contrast(p.text, page), greaterThanOrEqualTo(4.5), reason: 'text on page over $photo');
          }
        });
      }
    }

    test('colour-blind: success and errors are far apart in lightness and hue', () {
      final p = GwPalette.colorBlind;
      final s = HSLColor.fromColor(p.success).hue;
      final e = HSLColor.fromColor(p.errorText).hue;
      // blue against orange, not green against red
      expect(s, inInclusiveRange(190, 220));
      expect(e, inInclusiveRange(20, 40));
    });

    test('night: every colour is red (no green or blue light)', () {
      final p = GwPalette.night;
      for (final c in [p.accent, p.text, p.mutedText, p.surface1, p.success, p.alert, p.errorText, ...p.gradient]) {
        expect(c.g, lessThanOrEqualTo(c.r * 0.6), reason: '$c');
        expect(c.b, lessThanOrEqualTo(c.r * 0.6), reason: '$c');
      }
      expect(p.redOnly, isTrue);
      expect(GwPalette.stock.redOnly, isFalse);
    });

    test('the night filter drops green and blue, and keeps the text readable', () {
      expect(kNightVisionMatrix.sublist(5, 15), everyElement(0));
      expect(kNightVisionMatrix[18], 1); // alpha kept
      Color filtered(Color c) {
        final m = kNightVisionMatrix;
        final r = (m[0] * c.r + m[1] * c.g + m[2] * c.b).clamp(0.0, 1.0);
        return Color.from(alpha: 1, red: r, green: 0, blue: 0);
      }

      final p = GwPalette.night;
      final bg = filtered(p.background);
      expect(contrast(filtered(p.text), bg), greaterThanOrEqualTo(4.5));
      expect(contrast(filtered(p.mutedText), bg), greaterThanOrEqualTo(3.0));
      expect(contrast(filtered(p.text), filtered(p.surface2)), greaterThanOrEqualTo(4.5));
      expect(contrast(filtered(p.onAlert), filtered(p.alert)), greaterThanOrEqualTo(4.5));
      // a white photo or map tile comes out bright red, not white
      expect(filtered(Colors.white), const Color(0xFFFF0000));
    });
  });

  group('GwColors', () {
    test('reads the active palette', () {
      expect(GwColors.accent, GwPalette.stock.accent);
      GwColors.use(GwPalette.night, glass: true);
      expect(GwColors.accent, GwPalette.night.accent);
      expect(GwColors.background, Colors.black);
      expect(GwColors.glass, isTrue);
    });

    test('the theme is see-through only with glass', () {
      final solid = buildGhostWaveTheme(GwPalette.summer);
      expect(solid.scaffoldBackgroundColor, GwPalette.summer.background);
      expect(solid.colorScheme.primary, GwPalette.summer.accent);
      final glass = buildGhostWaveTheme(GwPalette.summer, true);
      expect(glass.scaffoldBackgroundColor, Colors.transparent);
      expect(glass.cardTheme.color!.a, closeTo(kGlassCardAlpha, 0.01));
    });
  });

  group('saved look', () {
    test('defaults to stock and solid', () async {
      final c = await container({});
      expect(c.read(lookProvider), const LookSettings());
      expect(c.read(paletteProvider), same(GwPalette.stock));
      expect(c.read(lookProvider).glass, isFalse);
    });

    test('theme and background are saved', () async {
      final c = await container({});
      c.read(lookProvider.notifier)
        ..setTheme(LookTheme.seasonal)
        ..setBackdrop(LookBackdrop.gradient);
      expect(c.read(paletteProvider), same(GwPalette.autumn));
      final prefs = c.read(sharedPrefsProvider);
      expect(prefs.getString('look_theme'), 'seasonal');
      expect(prefs.getString('look_backdrop'), 'gradient');
      final again = await container({'look_theme': 'colorBlind', 'look_backdrop': 'gradient'});
      expect(again.read(lookProvider).theme, LookTheme.colorBlind);
      expect(again.read(lookProvider).glass, isTrue);
    });

    test('unknown saved values fall back', () async {
      final c = await container({'look_theme': 'disco', 'look_backdrop': 'lava'});
      expect(c.read(lookProvider), const LookSettings());
    });

    test('night vision is always solid; photo without a photo is a gradient', () {
      const night = LookSettings(theme: LookTheme.night, backdrop: LookBackdrop.photo, photoPath: '/p.jpg');
      expect(night.effectiveBackdrop, LookBackdrop.solid);
      expect(night.glass, isFalse);
      const noPhoto = LookSettings(backdrop: LookBackdrop.photo);
      expect(noPhoto.effectiveBackdrop, LookBackdrop.gradient);
    });

    test('a background photo: picked, replaced (old copy deleted), removed', () async {
      final photos = FakePhotos();
      final c = await container({}, photos: photos);
      final look = c.read(lookProvider.notifier);
      expect(await look.pickPhoto(), isTrue);
      expect(c.read(lookProvider).photoPath, '/look/background-0.jpg');
      expect(c.read(lookProvider).effectiveBackdrop, LookBackdrop.photo);
      expect(await look.pickPhoto(), isTrue);
      expect(photos.removed, ['/look/background-0.jpg']);
      expect(c.read(sharedPrefsProvider).getString('look_photo'), '/look/background-1.jpg');
      look.removePhoto();
      expect(c.read(lookProvider).photoPath, isNull);
      expect(c.read(lookProvider).backdrop, LookBackdrop.gradient);
      expect(photos.removed, ['/look/background-0.jpg', '/look/background-1.jpg']);
      expect(c.read(sharedPrefsProvider).getString('look_photo'), isNull);
    });

    test('cancelling the picker changes nothing', () async {
      final photos = FakePhotos()..cancel = true;
      final c = await container({}, photos: photos);
      expect(await c.read(lookProvider.notifier).pickPhoto(), isFalse);
      expect(c.read(lookProvider), const LookSettings());
    });

    test('summary line', () {
      expect(lookSummary(const LookSettings(), DateTime(2026, 11, 14)), 'Stock · Solid background');
      expect(
        lookSummary(const LookSettings(theme: LookTheme.seasonal, backdrop: LookBackdrop.gradient), DateTime(2026, 7)),
        'Season (Summer) · Gradient background',
      );
    });
  });

  group('node looks', () {
    test('colour, photo, reset; saved by node ID', () async {
      final photos = FakePhotos();
      final c = await container({}, photos: photos);
      final looks = c.read(nodeLooksProvider.notifier);
      looks.setHue(0xCAFE0003, 195);
      expect(c.read(nodeLooksProvider)[0xCAFE0003], const NodeLook(hue: 195));
      expect(await looks.pickPhoto(0xCAFE0003), isTrue);
      expect(c.read(nodeLooksProvider)[0xCAFE0003], const NodeLook(photoPath: '/look/node-cafe0003-0.jpg'));
      // choosing a colour drops the photo and deletes it
      looks.setHue(0xCAFE0003, 25);
      expect(photos.removed, ['/look/node-cafe0003-0.jpg']);
      final saved = jsonDecode(c.read(sharedPrefsProvider).getString('node_looks')!);
      expect(saved, {
        'cafe0003': {'hue': 25},
      });
      looks.reset(0xCAFE0003);
      expect(c.read(nodeLooksProvider), isEmpty);
    });

    test('reset deletes every node photo', () async {
      final photos = FakePhotos();
      final c = await container({}, photos: photos);
      final looks = c.read(nodeLooksProvider.notifier);
      await looks.pickPhoto(1);
      await looks.pickPhoto(2);
      looks.setHue(3, 60);
      await looks.deletePhotos();
      expect(photos.removed, ['/look/node-00000001-0.jpg', '/look/node-00000002-1.jpg']);
    });

    test('loads saved looks and skips junk', () async {
      final c = await container({
        'node_looks': jsonEncode({
          'cafe0001': {'hue': 140},
          'cafe0003': {'photo': '/x.jpg'},
          'zz': {'hue': 1},
          'cafe0002': {'hue': 999},
          '0000abcd': 'nope',
        }),
      });
      expect(c.read(nodeLooksProvider), {
        0xCAFE0001: const NodeLook(hue: 140),
        0xCAFE0003: const NodeLook(photoPath: '/x.jpg'),
      });
    });

    test('a broken saved value is ignored', () async {
      final c = await container({'node_looks': '{not json'});
      expect(c.read(nodeLooksProvider), isEmpty);
    });

    test('a chosen colour keeps the mark, changes its hue', () {
      final spec = NodeMarkSpec.forNode(0xCAFE0003);
      final blue = spec.withHue(220);
      expect(blue.hue, 220);
      expect(blue.rings, spec.rings);
      expect(blue.core, spec.core);
      expect((blue.accentHue - blue.hue) % 360, (spec.accentHue - spec.hue) % 360);
    });
  });

  group('screens', () {
    Future<ProviderContainer> pump(WidgetTester tester, Widget home, {FakePhotos? photos}) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          lookPhotosProvider.overrideWithValue(photos ?? FakePhotos()),
          lookClockProvider.overrideWithValue(() => DateTime(2026, 11, 14)),
        ],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(theme: buildGhostWaveTheme(), home: home),
        ),
      );
      return c;
    }

    testWidgets('Look: pick a theme and a background', (tester) async {
      final handle = tester.ensureSemantics();
      final c = await pump(tester, const LookScreen());
      expect(find.text('Stock'), findsOneWidget);
      expect(find.textContaining('Now autumn'), findsOneWidget);
      await tester.tap(find.text('Night vision'));
      await tester.pump();
      expect(c.read(lookProvider).theme, LookTheme.night);
      expect(find.text('Night vision always uses a black background.'), findsOneWidget);
      await tester.tap(find.text('Colour-blind safe'));
      await tester.pump();
      await tester.tap(find.text('Gradient'));
      await tester.pump();
      expect(c.read(lookProvider).backdrop, LookBackdrop.gradient);
      expect(find.bySemanticsLabel('Preview of the chosen look'), findsOneWidget);
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('Look: Photo with no photo yet opens the picker', (tester) async {
      final photos = FakePhotos();
      final c = await pump(tester, const LookScreen(), photos: photos);
      await tester.tap(find.text('Photo'));
      await tester.pumpAndSettle();
      expect(photos.picked, hasLength(1));
      expect(c.read(lookProvider).effectiveBackdrop, LookBackdrop.photo);
      expect(find.text('Remove the photo'), findsOneWidget);
    });

    testWidgets('node picture sheet: pick a colour, then back to generated', (tester) async {
      final handle = tester.ensureSemantics();
      final c = await pump(
        tester,
        Builder(
          builder: (context) => Center(
            child: FilledButton(onPressed: () => showNodeLookSheet(context, 0xCAFE0003), child: const Text('open')),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Only on this phone. Never sent over the mesh.'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Colour, hue 220 degrees'));
      await tester.pump();
      expect(c.read(nodeLooksProvider)[0xCAFE0003], const NodeLook(hue: 220));
      expect(tester.getSemantics(find.bySemanticsLabel('Colour, hue 220 degrees')), isSemantics(isSelected: true));
      await tester.tap(find.text('Use the generated mark'));
      await tester.pump();
      expect(c.read(nodeLooksProvider), isEmpty);
      // 48 px colour targets
      expect(tester.getSize(find.bySemanticsLabel('Colour, hue 0 degrees')).width, greaterThanOrEqualTo(48));
      handle.dispose();
    });
  });
}

/// The gradient or photo behind every page when the look uses one. Each page
/// route paints its own copy, so pages stay opaque while they slide in.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/look.dart';
import 'theme.dart';

/// How dark the scrim over a background photo is, so text on frosted cards
/// and on the page keeps its contrast whatever the photo.
const double kPhotoScrimAlpha = 0.6;

/// Paints the chosen background under [child]. Plain [child] for a solid
/// background (the page's own colour does the job).
class PageBackdrop extends ConsumerWidget {
  /// Creates the backdrop.
  const PageBackdrop({required this.child, super.key});

  /// The page.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(lookProvider);
    if (!GwColors.glass) return child;
    final p = GwColors.palette;
    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: p.gradient),
      ),
    );
    final photo = look.photoPath;
    final back = look.effectiveBackdrop == LookBackdrop.photo && photo != null
        ? Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: p.background),
              Image.file(
                File(photo),
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => gradient,
              ),
              ColoredBox(color: p.background.withValues(alpha: kPhotoScrimAlpha)),
            ],
          )
        : gradient;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(child: back),
        child,
      ],
    );
  }
}

/// Wraps a platform's page transition so each page carries the backdrop.
class BackdropPageTransitionsBuilder extends PageTransitionsBuilder {
  /// Wraps [inner].
  const BackdropPageTransitionsBuilder(this.inner);

  /// The platform's own transition.
  final PageTransitionsBuilder inner;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => inner.buildTransitions(route, context, animation, secondaryAnimation, PageBackdrop(child: child));
}

/// The default page transitions, each wrapped with [PageBackdrop].
PageTransitionsTheme backdropPageTransitions() => PageTransitionsTheme(
  builders: {
    for (final e in const PageTransitionsTheme().builders.entries) e.key: BackdropPageTransitionsBuilder(e.value),
  },
);

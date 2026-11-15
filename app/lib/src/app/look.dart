/// How the app looks on this phone: the colour theme, the page background
/// (solid, gradient or a photo) and a picture or colour per node. All of it is
/// saved on this phone only and never sent over the mesh.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../ui/palettes.dart';
import 'providers.dart';

/// What sits behind the pages.
enum LookBackdrop {
  /// The theme's plain background colour.
  solid,

  /// A gradient in the theme's colours, with frosted cards.
  gradient,

  /// A photo the user picked, darkened, with frosted cards.
  photo;

  /// Name shown in settings.
  String get label => switch (this) {
    solid => 'Solid',
    gradient => 'Gradient',
    photo => 'Photo',
  };
}

/// The saved look.
@immutable
class LookSettings {
  /// Creates a look.
  const LookSettings({this.theme = LookTheme.stock, this.backdrop = LookBackdrop.solid, this.photoPath});

  /// Colour theme.
  final LookTheme theme;

  /// Background choice.
  final LookBackdrop backdrop;

  /// The background photo's file, kept even while another background is
  /// chosen so switching back needs no new pick.
  final String? photoPath;

  /// What actually shows: Night vision is always solid black, and Photo
  /// without a photo falls back to the gradient.
  LookBackdrop get effectiveBackdrop {
    if (theme == LookTheme.night) return LookBackdrop.solid;
    if (backdrop == LookBackdrop.photo && photoPath == null) return LookBackdrop.gradient;
    return backdrop;
  }

  /// Whether pages are see-through with frosted cards.
  bool get glass => effectiveBackdrop != LookBackdrop.solid;

  /// A copy with the given fields changed; [clearPhoto] drops the photo.
  LookSettings copyWith({LookTheme? theme, LookBackdrop? backdrop, String? photoPath, bool clearPhoto = false}) =>
      LookSettings(
        theme: theme ?? this.theme,
        backdrop: backdrop ?? this.backdrop,
        photoPath: clearPhoto ? null : photoPath ?? this.photoPath,
      );

  @override
  bool operator ==(Object other) =>
      other is LookSettings && other.theme == theme && other.backdrop == backdrop && other.photoPath == photoPath;

  @override
  int get hashCode => Object.hash(theme, backdrop, photoPath);
}

/// Picks photos and keeps copies in the app's own folder; tests override it.
abstract interface class LookPhotos {
  /// Lets the user pick a photo and copies it in under [name]; null when the
  /// user cancels. [maxSide] caps the stored size in pixels.
  Future<String?> pick(String name, {required double maxSide});

  /// Deletes a stored copy (no error if it is already gone).
  Future<void> remove(String path);
}

/// The real picker: the system photo picker, copies under app support.
class DeviceLookPhotos implements LookPhotos {
  /// Creates the picker.
  const DeviceLookPhotos();

  @override
  Future<String?> pick(String name, {required double maxSide}) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: maxSide,
      maxHeight: maxSide,
      imageQuality: 85,
    );
    if (picked == null) return null;
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/look');
    await dir.create(recursive: true);
    // a fresh name each time, so the image cache never shows the old picture
    final ext = picked.path.contains('.') ? picked.path.substring(picked.path.lastIndexOf('.')) : '.jpg';
    final out = '${dir.path}/$name-${DateTime.now().millisecondsSinceEpoch}$ext';
    await File(picked.path).copy(out);
    return out;
  }

  @override
  Future<void> remove(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // already gone
    }
  }
}

/// The photo picker.
final lookPhotosProvider = Provider<LookPhotos>((ref) => const DeviceLookPhotos());

/// Today's date; tests override it to pin the season.
final lookClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The saved look.
class LookNotifier extends Notifier<LookSettings> {
  static const _themeKey = 'look_theme';
  static const _backdropKey = 'look_backdrop';
  static const _photoKey = 'look_photo';

  @override
  LookSettings build() {
    final p = ref.watch(sharedPrefsProvider);
    T pick<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    return LookSettings(
      theme: pick(LookTheme.values, p.getString(_themeKey), LookTheme.stock),
      backdrop: pick(LookBackdrop.values, p.getString(_backdropKey), LookBackdrop.solid),
      photoPath: p.getString(_photoKey),
    );
  }

  /// Chooses the colour theme.
  void setTheme(LookTheme theme) {
    state = state.copyWith(theme: theme);
    unawaited(ref.read(sharedPrefsProvider).setString(_themeKey, theme.name));
  }

  /// Chooses the background.
  void setBackdrop(LookBackdrop backdrop) {
    state = state.copyWith(backdrop: backdrop);
    unawaited(ref.read(sharedPrefsProvider).setString(_backdropKey, backdrop.name));
  }

  /// Lets the user pick a background photo and switches to it; false if they
  /// cancelled.
  Future<bool> pickPhoto() async {
    final photos = ref.read(lookPhotosProvider);
    final path = await photos.pick('background', maxSide: 2048);
    if (path == null) return false;
    final old = state.photoPath;
    state = state.copyWith(photoPath: path, backdrop: LookBackdrop.photo);
    final p = ref.read(sharedPrefsProvider);
    unawaited(p.setString(_photoKey, path));
    unawaited(p.setString(_backdropKey, LookBackdrop.photo.name));
    if (old != null && old != path) unawaited(photos.remove(old));
    return true;
  }

  /// Forgets the background photo and deletes its copy.
  void removePhoto() {
    final old = state.photoPath;
    if (old == null) return;
    state = state.copyWith(
      clearPhoto: true,
      backdrop: state.backdrop == LookBackdrop.photo ? LookBackdrop.gradient : null,
    );
    final p = ref.read(sharedPrefsProvider);
    unawaited(p.remove(_photoKey));
    unawaited(p.setString(_backdropKey, state.backdrop.name));
    unawaited(ref.read(lookPhotosProvider).remove(old));
  }
}

/// The saved look.
final lookProvider = NotifierProvider<LookNotifier, LookSettings>(LookNotifier.new);

/// The palette in use now: the chosen theme on today's date.
final paletteProvider = Provider<GwPalette>((ref) {
  final theme = ref.watch(lookProvider.select((l) => l.theme));
  return GwPalette.forTheme(theme, ref.watch(lookClockProvider)());
});

/// A node's own look on this phone: a colour (hue) or a photo. Neither is
/// sent anywhere; other phones still see the generated mark.
@immutable
class NodeLook {
  /// Creates a look; at most one of [hue] and [photoPath] is used (the photo
  /// wins).
  const NodeLook({this.hue, this.photoPath});

  /// From saved JSON; null if it holds nothing usable.
  static NodeLook? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final hue = json['hue'];
    final photo = json['photo'];
    final look = NodeLook(
      hue: hue is int && hue >= 0 && hue < 360 ? hue : null,
      photoPath: photo is String && photo.isNotEmpty ? photo : null,
    );
    return look.isEmpty ? null : look;
  }

  /// Hue in degrees (0 to 359) for the mark's main colour.
  final int? hue;

  /// The node's photo.
  final String? photoPath;

  /// Whether nothing is set.
  bool get isEmpty => hue == null && photoPath == null;

  /// For saving.
  Map<String, Object?> toJson() => {'hue': ?hue, 'photo': ?photoPath};

  @override
  bool operator ==(Object other) => other is NodeLook && other.hue == hue && other.photoPath == photoPath;

  @override
  int get hashCode => Object.hash(hue, photoPath);
}

/// Hues offered for a node's colour, in degrees.
const List<int> kNodeHues = [0, 25, 45, 60, 95, 140, 175, 195, 220, 260, 290, 325];

/// Each node's own look, by node ID (saved).
class NodeLooksNotifier extends Notifier<Map<int, NodeLook>> {
  static const _key = 'node_looks';

  @override
  Map<int, NodeLook> build() {
    final raw = ref.watch(sharedPrefsProvider).getString(_key);
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return const {};
      final looks = <int, NodeLook>{};
      for (final e in decoded.entries) {
        final id = int.tryParse(e.key, radix: 16);
        final look = NodeLook.fromJson(e.value);
        if (id != null && look != null) looks[id] = look;
      }
      return looks;
    } on FormatException {
      return const {};
    }
  }

  void _save(Map<int, NodeLook> looks) {
    state = looks;
    final json = {for (final e in looks.entries) e.key.toRadixString(16): e.value.toJson()};
    unawaited(ref.read(sharedPrefsProvider).setString(_key, jsonEncode(json)));
  }

  /// Gives [nodeId] the colour [hue] (drops any photo).
  void setHue(int nodeId, int hue) {
    _dropPhoto(nodeId);
    _save({...state, nodeId: NodeLook(hue: hue % 360)});
  }

  /// Lets the user pick a photo for [nodeId]; false if they cancelled.
  Future<bool> pickPhoto(int nodeId) async {
    final path = await ref
        .read(lookPhotosProvider)
        .pick('node-${nodeId.toRadixString(16).padLeft(8, '0')}', maxSide: 512);
    if (path == null) return false;
    _dropPhoto(nodeId);
    _save({...state, nodeId: NodeLook(photoPath: path)});
    return true;
  }

  /// Back to the generated mark.
  void reset(int nodeId) {
    if (!state.containsKey(nodeId)) return;
    _dropPhoto(nodeId);
    _save({...state}..remove(nodeId));
  }

  /// Deletes every node photo copy (for Reset app data).
  Future<void> deletePhotos() async {
    final photos = ref.read(lookPhotosProvider);
    for (final look in state.values) {
      final path = look.photoPath;
      if (path != null) await photos.remove(path);
    }
  }

  void _dropPhoto(int nodeId) {
    final old = state[nodeId]?.photoPath;
    if (old != null) unawaited(ref.read(lookPhotosProvider).remove(old));
  }
}

/// Each node's own look.
final nodeLooksProvider = NotifierProvider<NodeLooksNotifier, Map<int, NodeLook>>(NodeLooksNotifier.new);

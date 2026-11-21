/// The team's SARNEG code words, kept in the platform's secure storage.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/sarneg.dart';

/// Where the code words are saved.
abstract interface class SarnegStore {
  /// The saved JSON, or null when none.
  Future<String?> read();

  /// Saves [json].
  Future<void> write(String json);

  /// Forgets the code words.
  Future<void> clear();
}

/// [SarnegStore] in memory (tests).
class MemorySarnegStore implements SarnegStore {
  /// Starts with [value].
  MemorySarnegStore([this.value]);

  /// What is saved.
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async => value = json;

  @override
  Future<void> clear() async => value = null;
}

/// [SarnegStore] in the Android Keystore / iOS Keychain.
class SecureSarnegStore implements SarnegStore {
  /// Creates the store.
  const SecureSarnegStore();

  static const _storage = FlutterSecureStorage();
  static const _key = 'sarneg_keys';

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String json) => _storage.write(key: _key, value: json);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// The store; overridden in tests.
final sarnegStoreProvider = Provider<SarnegStore>((ref) => const SecureSarnegStore());

/// The clock that picks the day's word; overridden in tests.
final sarnegClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The saved code words; null when none are set.
class SarnegController extends AsyncNotifier<SarnegKeySet?> {
  @override
  Future<SarnegKeySet?> build() async {
    final raw = await ref.watch(sarnegStoreProvider).read();
    if (raw == null) return null;
    try {
      final keys = SarnegKeySet.fromJson(jsonDecode(raw));
      // dated words for past days are no use any more
      return keys?.withoutDaysBefore(sarnegDay(ref.read(sarnegClockProvider)()));
    } on FormatException {
      return null;
    }
  }

  /// Saves [keys] (null forgets them).
  Future<void> save(SarnegKeySet? keys) async {
    final store = ref.read(sarnegStoreProvider);
    if (keys == null) {
      await store.clear();
    } else {
      await store.write(jsonEncode(keys.toJson()));
    }
    state = AsyncData(keys);
  }

  /// The codec for [at] (today when null), or null when no word is set.
  SarnegCodec? codecFor([DateTime? at]) => state.value?.codecFor(at ?? ref.read(sarnegClockProvider)());
}

/// The team's code words.
final sarnegProvider = AsyncNotifierProvider<SarnegController, SarnegKeySet?>(SarnegController.new);

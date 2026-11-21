// SARNEG: Search And Rescue Numerical Encryption Grid.
//
// A team agrees on a 10-letter code word with no repeated letter. Letter 1
// stands for 0, letter 2 for 1, and so on, so with BLACKHORSE the number 17
// is sent as LR. It hides numbers from a casual listener. It is NOT
// encryption: anyone who hears a few messages can work the word out.
//
// Wire format shared by GhostWave and every NOTORYX app, so they can read
// each other's messages:
//
//   [SARNEG] LRs KSAC
//
// After the marker, each digit becomes its code letter in UPPER case and
// every other letter is sent in lower case, so decoding never mistakes a
// plain letter for a digit. Everything else (spaces, '.', '-', ',', ':')
// goes as is.
//
// The code word moves between phones as text or a QR code:
//
//   SARNEG1:BLACKHORSE;2026-11-21=CUMBERLAND;2026-11-22=DUMBWAITER
//
// The first word is the default. Each dated entry replaces it on that
// local calendar day, so a team can load a week of words at once.

/// Put at the start of a message whose body is SARNEG-encoded.
const String kSarnegMarker = '[SARNEG]';

/// Start of a shared code word (text or QR code).
const String kSarnegSharePrefix = 'SARNEG1:';

/// Most dated words one code set holds.
const int kSarnegMaxDailyWords = 62;

/// Why a code word cannot be used.
enum SarnegWordProblem {
  /// Not exactly 10 letters.
  length,

  /// Something other than the letters A to Z.
  letters,

  /// A letter appears twice.
  repeats,
}

/// [word] trimmed, without spaces, in upper case.
String normalizeSarnegWord(String word) => word.replaceAll(RegExp(r'\s'), '').toUpperCase();

/// What is wrong with [word] (already normalized), or null when it can be used.
SarnegWordProblem? checkSarnegWord(String word) {
  if (!RegExp(r'^[A-Z]*$').hasMatch(word)) return SarnegWordProblem.letters;
  if (word.length != 10) return SarnegWordProblem.length;
  if (word.split('').toSet().length != 10) return SarnegWordProblem.repeats;
  return null;
}

/// Turns digits into letters and back with one code word.
class SarnegCodec {
  /// Uses [word], which must pass [checkSarnegWord].
  SarnegCodec(this.word) {
    if (checkSarnegWord(word) != null) throw ArgumentError.value(word, 'word', 'not a SARNEG code word');
  }

  /// The 10-letter code word.
  final String word;

  static final RegExp _digit = RegExp(r'[0-9]');

  /// [plain] with every digit replaced by its code letter (upper case) and
  /// every other letter in lower case.
  String encode(String plain) {
    final out = StringBuffer();
    for (final ch in plain.split('')) {
      if (_digit.hasMatch(ch)) {
        out.write(word[int.parse(ch)]);
      } else {
        out.write(ch.toLowerCase());
      }
    }
    return out.toString();
  }

  /// [coded] with every upper-case code letter turned back into its digit.
  /// Lower-case letters and everything else stay as they are.
  String decode(String coded) {
    final out = StringBuffer();
    for (final ch in coded.split('')) {
      final i = word.indexOf(ch);
      out.write(i >= 0 ? '$i' : ch);
    }
    return out.toString();
  }

  /// A whole message ready to send: the marker, a space and [plain] encoded.
  String encodeMessage(String plain) => '$kSarnegMarker ${encode(plain.trim())}';

  /// The plain text of [message], or null when it has no SARNEG marker.
  String? decodeMessage(String message) {
    final body = sarnegBody(message);
    return body == null ? null : decode(body);
  }
}

/// Whether [message] starts with the SARNEG marker.
bool isSarnegMessage(String message) => message.trimLeft().startsWith(kSarnegMarker);

/// What follows the marker in [message], or null when there is no marker.
String? sarnegBody(String message) {
  final t = message.trimLeft();
  if (!t.startsWith(kSarnegMarker)) return null;
  return t.substring(kSarnegMarker.length).trim();
}

/// `yyyy-mm-dd` for the local calendar day of [t].
String sarnegDay(DateTime t) {
  final l = t.isUtc ? t.toLocal() : t;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year.toString().padLeft(4, '0')}-${two(l.month)}-${two(l.day)}';
}

/// A team's code words: a default plus optional words for given days.
class SarnegKeySet {
  /// Creates a set. Every word must pass [checkSarnegWord].
  SarnegKeySet({required this.word, Map<String, String> daily = const {}})
    : daily = Map.unmodifiable(Map.fromEntries(daily.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) {
    if (checkSarnegWord(word) != null) throw ArgumentError.value(word, 'word', 'not a SARNEG code word');
    if (this.daily.length > kSarnegMaxDailyWords) throw ArgumentError('more than $kSarnegMaxDailyWords dated words');
    for (final e in this.daily.entries) {
      if (!_dayPattern.hasMatch(e.key)) throw ArgumentError.value(e.key, 'daily', 'not a yyyy-mm-dd day');
      if (checkSarnegWord(e.value) != null) throw ArgumentError.value(e.value, 'daily', 'not a SARNEG code word');
    }
  }

  static final RegExp _dayPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Used on any day without its own word.
  final String word;

  /// Words for given local days, keyed `yyyy-mm-dd`, in date order.
  final Map<String, String> daily;

  /// The word for the local day of [at].
  String wordFor(DateTime at) => daily[sarnegDay(at)] ?? word;

  /// A codec for the local day of [at].
  SarnegCodec codecFor(DateTime at) => SarnegCodec(wordFor(at));

  /// This set with [day]'s word set to [dayWord], or removed when null.
  SarnegKeySet withDay(String day, String? dayWord) {
    final next = Map<String, String>.of(daily);
    if (dayWord == null) {
      next.remove(day);
    } else {
      next[day] = dayWord;
    }
    return SarnegKeySet(word: word, daily: next);
  }

  /// This set without dated words for days before [today] (`yyyy-mm-dd`).
  SarnegKeySet withoutDaysBefore(String today) => SarnegKeySet(
    word: word,
    daily: {
      for (final e in daily.entries)
        if (e.key.compareTo(today) >= 0) e.key: e.value,
    },
  );

  /// The text to share or show as a QR code.
  String toShareText() => ['$kSarnegSharePrefix$word', for (final e in daily.entries) '${e.key}=${e.value}'].join(';');

  /// Reads [text] made by [toShareText]. Throws [FormatException] when it is
  /// not a code set.
  static SarnegKeySet parseShareText(String text) {
    final t = text.trim();
    if (!t.toUpperCase().startsWith(kSarnegSharePrefix)) {
      throw const FormatException('Not a SARNEG code word');
    }
    final parts = t.substring(kSarnegSharePrefix.length).split(';');
    final word = normalizeSarnegWord(parts.first);
    if (checkSarnegWord(word) != null) throw const FormatException('The code word is not 10 different letters');
    final daily = <String, String>{};
    for (final p in parts.skip(1)) {
      if (p.trim().isEmpty) continue;
      final eq = p.indexOf('=');
      if (eq < 0) throw const FormatException('A dated word is missing its date');
      final day = p.substring(0, eq).trim();
      final w = normalizeSarnegWord(p.substring(eq + 1));
      if (!_dayPattern.hasMatch(day) || !_validDay(day)) throw FormatException('Not a date: $day');
      if (checkSarnegWord(w) != null) throw FormatException('The word for $day is not 10 different letters');
      daily[day] = w;
    }
    if (daily.length > kSarnegMaxDailyWords) throw const FormatException('Too many dated words');
    return SarnegKeySet(word: word, daily: daily);
  }

  static bool _validDay(String day) {
    final d = DateTime.tryParse(day);
    return d != null && sarnegDay(d) == day;
  }

  /// For saving.
  Map<String, Object> toJson() => {'word': word, 'daily': daily};

  /// Reads [toJson] output; null when it is damaged.
  static SarnegKeySet? fromJson(Object? json) {
    try {
      if (json is! Map) return null;
      final word = json['word'];
      final daily = json['daily'];
      if (word is! String) return null;
      return SarnegKeySet(
        word: word,
        daily: daily is Map ? {for (final e in daily.entries) '${e.key}': '${e.value}'} : const {},
      );
    } on ArgumentError {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SarnegKeySet &&
      other.word == word &&
      other.daily.length == daily.length &&
      daily.entries.every((e) => other.daily[e.key] == e.value);

  @override
  int get hashCode => Object.hash(word, Object.hashAllUnordered(daily.entries.map((e) => '${e.key}=${e.value}')));
}

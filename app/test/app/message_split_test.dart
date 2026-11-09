import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/data/message_split.dart';

void main() {
  int size(String s) => utf8.encode(s).length;
  String body(String part) => part.replaceFirst(RegExp(r'^\(\d/\d\) '), '');

  test('a message that fits is left alone', () {
    final t = 'x' * 73;
    expect(splitMessage(t, 73), [t]);
  });

  test('one byte over becomes two labelled parts', () {
    final parts = splitMessage('x' * 74, 73);
    expect(parts.length, 2);
    expect(parts[0], startsWith('(1/2) '));
    expect(parts[1], startsWith('(2/2) '));
    expect(parts.every((p) => size(p) <= 73), isTrue);
  });

  test('breaks at spaces and keeps every word', () {
    final text = List.generate(40, (i) => 'word$i').join(' ');
    final parts = splitMessage(text, 73);
    expect(parts.every((p) => size(p) <= 73), isTrue);
    expect(parts.map(body).join(' '), text);
  });

  test('never cuts inside a character', () {
    final text = '🏔é' * 60;
    final parts = splitMessage(text, 73);
    expect(parts.every((p) => size(p) <= 73), isTrue);
    expect(parts.map(body).join(), text);
  });

  test('can exceed the limit, so the caller can refuse it', () {
    expect(splitMessage('x' * 2000, 73).length, greaterThan(kMaxMessageParts));
  });
}

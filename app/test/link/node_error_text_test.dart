import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/session.dart';

void main() {
  test('every known error code has its own text, never a bare number', () {
    for (final code in pb.Error_Code.values) {
      if (code == pb.Error_Code.NONE) continue;
      final text = NodeError(code, '').message;
      expect(text, isNot(startsWith('Error ')), reason: code.name);
    }
  });

  test('NO_KEY says what to do next', () {
    expect(const NodeError(pb.Error_Code.NO_KEY, '').message, contains('send again'));
  });
}

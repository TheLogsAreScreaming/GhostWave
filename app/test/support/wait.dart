// Waiting on real file I/O in tests: pumpEventQueue alone does not wait for
// a history file to be read and opened, which is slow on CI runners.
import 'package:flutter_test/flutter_test.dart';

/// Pumps the event queue, with short real delays, until [done] holds (up to
/// [timeout]); the test's own expect then reports what is wrong if it never
/// does.
Future<void> settleUntil(bool Function() done, {Duration timeout = const Duration(seconds: 5)}) async {
  final stop = DateTime.now().add(timeout);
  await pumpEventQueue(times: 50);
  while (!done() && DateTime.now().isBefore(stop)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await pumpEventQueue(times: 20);
  }
}

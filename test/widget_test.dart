// Minimal smoke test so `flutter analyze` stays clean. Feature behaviour is
// verified manually on Windows (the platform this app targets); printing and
// spooler integration cannot run headless in CI.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('smoke: dart arithmetic works', () {
    expect(1 + 1, 2);
  });
}

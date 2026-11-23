import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Packages stay the approved ones (APP-REPORT §7); unused ones go.
void main() {
  test('mocktail is gone (no test used it)', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('mocktail'), isFalse);
  });
}

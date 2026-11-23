import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android lint's release check ("lint vital") stays on: it stops a release
/// build that would crash on some phones.
void main() {
  test('release builds run Android lint', () {
    final build = File('android/app/build.gradle.kts').readAsStringSync();
    expect(build.contains('checkReleaseBuilds = false'), isFalse);
    expect(build.contains('abortOnError = false'), isFalse);
  });

  test('lint runs from a version that reads every plugin', () {
    final props = File('android/gradle.properties').readAsStringSync();
    expect(props, contains('android.experimental.lint.version=9.5.2'));
  });
}

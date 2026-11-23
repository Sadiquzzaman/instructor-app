import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Release builds (the test APKs on GitHub and the Play Store build) only
/// get the permissions declared in the main manifest; debug builds add
/// INTERNET by themselves, so a missing one only shows on a real install.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  bool declares(String permission) => manifest.contains(
    '<uses-permission android:name="android.permission.$permission" />',
  );

  test('release builds can reach the server', () {
    expect(declares('INTERNET'), isTrue);
  });

  test('the permissions the features need are declared', () {
    // Check-in (location) and IELTS Speaking (microphone).
    for (final p in ['ACCESS_FINE_LOCATION', 'RECORD_AUDIO']) {
      expect(declares(p), isTrue, reason: p);
    }
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:instructor_app/core/theme/tokens.g.dart';

// The app icon and splash (generated from assets/brand/ by
// flutter_launcher_icons and flutter_native_splash, configured in pubspec.yaml)
// stay in step with the theme and the platform files.

String _hex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('the splash colour is the canvas token', () {
    final canvas = _hex(Tokens.colorCanvas.toARGB32());
    final colours = RegExp(
      r'^\s+color: "(#[0-9A-Fa-f]{6})"',
      multiLine: true,
    ).allMatches(pubspec).map((m) => m[1]!.toUpperCase()).toList();
    expect(colours, hasLength(2)); // before Android 12, and from 12 on
    expect(colours, everyElement(canvas));
    expect(
      File('android/app/src/main/res/values-v31/styles.xml').readAsStringSync(),
      contains('<item name="android:windowSplashScreenBackground">$canvas'),
    );
  });

  test('the icon and splash images are in place on both platforms', () {
    for (final path in [
      'assets/brand/icon.png',
      'assets/brand/icon-foreground.png',
      'assets/brand/logo.png',
      'assets/brand/splash-android12.png',
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
      'android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png',
      'android/app/src/main/res/drawable-xxxhdpi/android12splash.png',
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
      'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
    // The manifest keeps the standard icon name the generator overwrites.
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains('android:icon="@mipmap/ic_launcher"'),
    );
    expect(
      File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml')
          .readAsStringSync(),
      contains('@drawable/ic_launcher_foreground'),
    );
  });
}

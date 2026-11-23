import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// iOS shows the permission texts from InfoPlist.strings in the phone's
/// language; Bangla needs its own file, listed in the Xcode project.
void main() {
  const keys = [
    'NSCameraUsageDescription',
    'NSLocationWhenInUseUsageDescription',
    'NSMicrophoneUsageDescription',
    'NSPhotoLibraryUsageDescription',
  ];

  Map<String, String> strings(String lang) {
    final text = File('ios/Runner/$lang.lproj/InfoPlist.strings')
        .readAsStringSync();
    return {
      for (final m in RegExp(r'"(\w+)" = "([^"]+)";').allMatches(text))
        m.group(1)!: m.group(2)!,
    };
  }

  test('every permission text is in English and Bangla', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final en = strings('en');
    final bn = strings('bn');
    for (final k in keys) {
      expect(plist, contains('<key>$k</key>'), reason: k);
      // English matches Info.plist, which iOS uses when nothing else fits.
      expect(plist, contains('<string>${en[k]}</string>'), reason: k);
      expect(bn[k], isNotNull, reason: k);
      expect(RegExp('[ঀ-৿]').hasMatch(bn[k]!), isTrue, reason: k);
    }
    expect(en.keys.toSet(), keys.toSet());
    expect(bn.keys.toSet(), keys.toSet());
  });

  test('the app says it speaks Bangla, and Xcode bundles the texts', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<key>CFBundleLocalizations</key>'));
    expect(plist, contains('<string>bn</string>'));
    final project = File('ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();
    expect(project, contains('path = bn.lproj/InfoPlist.strings;'));
    expect(project, contains('path = en.lproj/InfoPlist.strings;'));
    expect(project, contains('/* InfoPlist.strings in Resources */,'));
    expect(project, contains('\t\t\t\tbn,\n'));
  });
}

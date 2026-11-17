import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CLAUDE.md: "no hard-coded colours or font sizes in widgets". Colours and
/// sizes live in lib/core/theme/ (generated from the web's tokens); everything
/// else reads them from the theme.
void main() {
  test('no raw colours or font sizes outside lib/core/theme/', () {
    final banned = <String, RegExp>{
      'a raw colour (Color(0x…))': RegExp(r'\bColor\(0x'),
      'a raw colour (Color.fromRGBO/fromARGB)': RegExp(
        r'\bColor\.from(RGBO|ARGB)\(',
      ),
      'a Material colour constant (Colors.…)': RegExp(r'\bColors\.\w+'),
      'a raw font size (fontSize:)': RegExp(r'\bfontSize\s*:'),
    };
    final offences = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where(
          (f) => !f.path.replaceAll(r'\', '/').contains('lib/core/theme/'),
        );

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final MapEntry(:key, :value) in banned.entries) {
          if (value.hasMatch(lines[i])) {
            offences.add('${file.path}:${i + 1}: $key');
          }
        }
      }
    }
    expect(offences, isEmpty, reason: offences.join('\n'));
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The web's messages name levels as tokens ("[[Section]]", "[[classes]]")
/// that each school words its own way. Every message that has one must go
/// through `ref.levels(context, …)`, or people see the raw token (found on
/// the report cards' section picker on the device, 19 Nov).
void main() {
  test('messages with level tokens are always passed to ref.levels', () {
    final keys = <String>{};
    void walk(String prefix, Object? v) {
      if (v is Map) {
        v.forEach((k, x) => walk(prefix.isEmpty ? '$k' : '$prefix.$k', x));
      } else if (v is String && v.contains('[[')) {
        final parts = prefix.split('.');
        keys.add(
          parts.first +
              parts
                  .skip(1)
                  .map(
                    (p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1),
                  )
                  .join(),
        );
      }
    }

    walk('', jsonDecode(File('l10n/web/en.json').readAsStringSync()));
    expect(keys, isNotEmpty);

    final offences = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('.g.dart'))
        .where((f) => !f.path.replaceAll(r'\', '/').contains('/generated/'));
    for (final file in files) {
      final s = file.readAsStringSync();
      for (final m in RegExp(r'l10n\.(\w+)').allMatches(s)) {
        if (!keys.contains(m[1])) continue;
        if (_insideLevels(s, m.start)) continue;
        final line = '\n'.allMatches(s.substring(0, m.start)).length + 1;
        offences.add('${file.path}:$line ${m[1]}');
      }
    }
    expect(offences, isEmpty, reason: offences.join('\n'));
  });
}

/// Whether [at] sits inside an open `levels(` call.
bool _insideLevels(String s, int at) {
  final from = s.lastIndexOf('levels(', at);
  if (from < 0 || at - from > 400) return false;
  var depth = 0;
  for (var i = from + 'levels'.length; i < at; i++) {
    if (s[i] == '(') depth++;
    if (s[i] == ')') depth--;
  }
  return depth > 0;
}

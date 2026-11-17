// Builds the app's message files (lib/l10n/app_en.arb, app_bn.arb) from the
// web's wording plus the app's own strings, so both apps say the same thing
// (CLAUDE.md "Text", STAGE-0-PLAN.md §7).
//
//   dart run tool/import_web_messages.dart                         # rebuild the ARB files
//   dart run tool/import_web_messages.dart ../tes-taker/frontend/messages
//                       # first refresh l10n/web/ from the web's en.json and bn.json
//
// Sources (edit these, never the ARB files):
//   l10n/web/{en,bn}.json  the web's namespaces listed in [webNamespaces], copied as they are
//   l10n/app/{en,bn}.json  strings only the app has, under the "app" namespace
//
// Keys are flattened to camelCase: auth.logIn → authLogIn. Messages keep the
// web's ICU syntax with two rewrites Flutter's gen-l10n needs:
//   {count, number} → {count} (a number placeholder, formatted per language)
//   # inside a plural branch → {count}
// Rich tags (<highlight>…</highlight>) and level tokens ([[Classes]]) stay in
// the text; RichMessage and LevelLabels handle them at runtime.
//
// test/l10n/messages_test.dart fails when the ARB files are out of date.
import 'dart:convert';
import 'dart:io';

/// The web namespaces the app uses so far. Add a namespace when a screen needs it.
const webNamespaces = ['common', 'language', 'ui', 'validation', 'auth', 'shell'];

const locales = ['en', 'bn'];

void main(List<String> args) {
  if (args.isNotEmpty) {
    for (final locale in locales) {
      final all = jsonDecode(
        File('${args.first}/$locale.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final picked = <String, dynamic>{};
      for (final ns in webNamespaces) {
        if (!all.containsKey(ns)) {
          throw StateError('The web has no "$ns" namespace in $locale.json');
        }
        picked[ns] = all[ns];
      }
      File('l10n/web/$locale.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(picked)}\n',
      );
      stdout.writeln(
        'Copied ${webNamespaces.join(', ')} to l10n/web/$locale.json',
      );
    }
  }
  for (final MapEntry(:key, :value) in buildArbFiles().entries) {
    File(key).writeAsStringSync(value);
    stdout.writeln('Wrote $key');
  }
}

/// ARB file path → contents, built from the sources in l10n/.
Map<String, String> buildArbFiles() {
  Map<String, dynamic> read(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final template = <String, String>{};
  final out = <String, String>{};
  for (final locale in locales) {
    final merged = <String, dynamic>{
      ...read('l10n/web/$locale.json'),
      ...read('l10n/app/$locale.json'),
    };
    final flat = flatten(merged);
    if (locale == 'en') template.addAll(flat);
    out['lib/l10n/app_$locale.arb'] = toArb(
      locale,
      flat,
      withMetadata: locale == 'en',
    );
  }
  return out;
}

/// Nested messages → flat camelCase keys, failing on clashes and bad names.
Map<String, String> flatten(Map<String, dynamic> tree) {
  final out = <String, String>{};
  final origin = <String, String>{};
  void walk(Map<String, dynamic> node, List<String> path) {
    for (final MapEntry(:key, :value) in node.entries) {
      final p = [...path, key];
      if (value is Map<String, dynamic>) {
        walk(value, p);
        continue;
      }
      final name = camelKey(p);
      if (!RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(name)) {
        throw FormatException('"${p.join('.')}" makes the invalid key "$name"');
      }
      if (origin.containsKey(name)) {
        throw FormatException(
          '"${p.join('.')}" and "${origin[name]}" both make "$name"',
        );
      }
      origin[name] = p.join('.');
      out[name] = value as String;
    }
  }

  walk(tree, []);
  return out;
}

/// ['ui', 'fileDrop', 'prompt'] → uiFileDropPrompt.
String camelKey(List<String> path) {
  final words = path
      .expand((p) => p.split(RegExp('[-_]')))
      .where((w) => w.isNotEmpty)
      .toList();
  return words.first[0].toLowerCase() +
      words.first.substring(1) +
      words.skip(1).map((w) => w[0].toUpperCase() + w.substring(1)).join();
}

String toArb(
  String locale,
  Map<String, String> messages, {
  required bool withMetadata,
}) {
  final arb = <String, dynamic>{'@@locale': locale};
  for (final MapEntry(:key, :value) in messages.entries) {
    final converted = convertMessage(value, key: key);
    arb[key] = converted.text;
    if (withMetadata && converted.placeholders.isNotEmpty) {
      arb['@$key'] = {
        'placeholders': {
          for (final MapEntry(key: name, value: type)
              in converted.placeholders.entries)
            name: type == PlaceholderType.number
                ? {'type': 'num', 'format': 'decimalPattern'}
                : {'type': 'String'},
        },
      };
    }
  }
  return '${const JsonEncoder.withIndent('  ').convert(arb)}\n';
}

enum PlaceholderType { text, number }

class ConvertedMessage {
  ConvertedMessage(this.text, this.placeholders);
  final String text;
  final Map<String, PlaceholderType> placeholders;
}

/// Parses one ICU message and rewrites what gen-l10n cannot read.
ConvertedMessage convertMessage(String message, {String key = ''}) {
  final parser = _IcuParser(message, key);
  final text = parser.parseMessage(pluralArg: null);
  if (parser.pos != message.length) {
    throw FormatException('Unexpected "}" in $key: $message');
  }
  return ConvertedMessage(text, parser.placeholders);
}

class _IcuParser {
  _IcuParser(this.src, this.key);
  final String src;
  final String key;
  int pos = 0;
  final placeholders = <String, PlaceholderType>{};

  void _type(String name, PlaceholderType type) {
    // A placeholder used as a number anywhere is a number.
    if (placeholders[name] != PlaceholderType.number) placeholders[name] = type;
  }

  /// Text until an unmatched "}" or the end.
  String parseMessage({required String? pluralArg}) {
    final b = StringBuffer();
    while (pos < src.length) {
      final c = src[pos];
      if (c == '}') break;
      if (c == '{') {
        b.write(_parseArgument());
      } else if (c == '#' && pluralArg != null) {
        b.write('{$pluralArg}');
        pos++;
      } else {
        b.write(c);
        pos++;
      }
    }
    return b.toString();
  }

  String _parseArgument() {
    pos++; // {
    final name = _word();
    _spaces();
    if (_peek('}')) {
      pos++;
      _type(name, PlaceholderType.text);
      return '{$name}';
    }
    _expect(',');
    _spaces();
    final kind = _word();
    _spaces();
    switch (kind) {
      case 'number':
        _expect('}');
        _type(name, PlaceholderType.number);
        return '{$name}';
      case 'plural' || 'select':
        _expect(',');
        final cases = StringBuffer();
        while (true) {
          _spaces();
          if (_peek('}')) break;
          final selector = _selector();
          _spaces();
          _expect('{');
          final body = parseMessage(pluralArg: kind == 'plural' ? name : null);
          _expect('}');
          cases.write(' $selector{$body}');
        }
        pos++; // }
        _type(
          name,
          kind == 'plural' ? PlaceholderType.number : PlaceholderType.text,
        );
        return '{$name, $kind,$cases}';
      default:
        throw FormatException('Unsupported "{$name, $kind}" in $key');
    }
  }

  String _word() {
    final m = RegExp(r'[A-Za-z_][A-Za-z0-9_]*').matchAsPrefix(src, pos);
    if (m == null) throw FormatException('Expected a name at $pos in $key');
    pos = m.end;
    return m[0]!;
  }

  String _selector() {
    final m = RegExp(r'=?[A-Za-z0-9_]+').matchAsPrefix(src, pos);
    if (m == null) throw FormatException('Expected a case at $pos in $key');
    pos = m.end;
    return m[0]!;
  }

  void _spaces() {
    while (pos < src.length && src[pos].trim().isEmpty) {
      pos++;
    }
  }

  bool _peek(String s) => src.startsWith(s, pos);

  void _expect(String s) {
    if (!_peek(s)) throw FormatException('Expected "$s" at $pos in $key');
    pos += s.length;
  }
}

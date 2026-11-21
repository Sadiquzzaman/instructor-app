import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:instructor_app/core/l10n/level_labels.dart';

import '../../tool/import_web_messages.dart';

/// Mirrors the web's frontend/i18n/messages.test.ts, plus a check that the
/// ARB files are what the import tool builds from l10n/.
void main() {
  Map<String, dynamic> arb(String locale) =>
      jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
          as Map<String, dynamic>;
  Map<String, String> messages(String locale) => {
    for (final MapEntry(:key, :value) in arb(locale).entries)
      if (!key.startsWith('@')) key: value as String,
  };

  // Latin text that is right in Bangla too (the same list as the web's).
  // Kept in Latin letters on purpose: the language names, and the exam's
  // name (the web's own Bangla is "IELTS").
  // The web's Bangla keeps these in Latin letters (a language name, IELTS).
  const latinInBangla = {
    'languageSwitchTo',
    'testsCategoryIelts',
    'createTestCategoriesIelts',
  };

  test('the ARB files are up to date with l10n/ '
      '(run `dart run tool/import_web_messages.dart`)', () {
    for (final MapEntry(:key, :value) in buildArbFiles().entries) {
      expect(File(key).readAsStringSync(), value, reason: key);
    }
  });

  test('Bangla and English have the same keys', () {
    expect(messages('bn').keys.toSet(), messages('en').keys.toSet());
  });

  test('no message is empty', () {
    for (final locale in ['en', 'bn']) {
      for (final MapEntry(:key, :value) in messages(locale).entries) {
        expect(value.trim(), isNotEmpty, reason: '$locale $key');
      }
    }
  });

  test('both languages use the same placeholders, tags and level tokens', () {
    final tag = RegExp(r'</?(\w+)>');
    Set<String> marks(String s) => {
      // The real placeholders (not text inside select or plural branches).
      ...convertMessage(s).placeholders.keys.map((p) => '{$p}'),
      ...tag.allMatches(s).map((m) => '<${m[1]}>'),
      // By level only: Bangla has one word per level, so English
      // [[Classes]] and Bangla [[class]] are the same mark.
      ...LevelLabels.tokenPattern
          .allMatches(s)
          .map(
            (m) => m[1]!.toLowerCase().startsWith('class')
                ? '[[class]]'
                : '[[section]]',
          ),
    };
    final bn = messages('bn');
    for (final MapEntry(:key, :value) in messages('en').entries) {
      expect(marks(bn[key]!), marks(value), reason: key);
    }
  });

  test('every Bangla message is actually in Bangla', () {
    for (final MapEntry(:key, :value) in messages('bn').entries) {
      if (latinInBangla.contains(key)) continue;
      // As shown: level tokens become Bangla words ([[class]] → ক্লাস).
      final shown = LevelLabels.defaults.apply(value, 'bn');
      expect(shown, matches(RegExp('[ঀ-৿]')), reason: key);
    }
  });

  group('convertMessage', () {
    test('plain placeholders are text', () {
      final m = convertMessage('Remove {name}');
      expect(m.text, 'Remove {name}');
      expect(m.placeholders, {'name': PlaceholderType.text});
    });

    test('a Dart reserved word as a placeholder gets "Value" added', () {
      final m = convertMessage(
        '{new, plural, one {# new mark} other {# new marks}}, was {old}, now {new}',
      );
      expect(
        m.text,
        '{newValue, plural, one{{newValue} new mark} other{{newValue} new marks}}'
        ', was {old}, now {newValue}',
      );
      expect(m.placeholders, {
        'newValue': PlaceholderType.number,
        'old': PlaceholderType.text,
      });
    });

    test('{x, number} becomes a number placeholder', () {
      final m = convertMessage('Step {current, number} of {total, number}');
      expect(m.text, 'Step {current} of {total}');
      expect(m.placeholders, {
        'current': PlaceholderType.number,
        'total': PlaceholderType.number,
      });
    });

    test('select branches are text, not placeholders', () {
      final m = convertMessage(
        '{field, select, newPassword {New password} other {Password}} is short',
      );
      expect(
        m.text,
        '{field, select, newPassword{New password} other{Password}} is short',
      );
      expect(m.placeholders, {'field': PlaceholderType.text});
    });

    test('# in a plural becomes the count, nested placeholders are found', () {
      final m = convertMessage(
        '{count, plural, =0 {No tests} one {# test by {name}} other {# tests}}',
      );
      expect(
        m.text,
        '{count, plural, =0{No tests} one{{count} test by {name}} other{{count} tests}}',
      );
      expect(m.placeholders, {
        'count': PlaceholderType.number,
        'name': PlaceholderType.text,
      });
    });

    test('tags and level tokens are left in the text', () {
      expect(
        convertMessage('Open <b>[[Classes]]</b>').text,
        'Open <b>[[Classes]]</b>',
      );
    });

    test('unsupported formats fail loudly', () {
      expect(
        () => convertMessage('{when, date, short}'),
        throwsFormatException,
      );
    });
  });

  group('flatten', () {
    test('camelCases nested keys', () {
      expect(
        flatten({
          'ui': {
            'fileDrop': {'prompt': 'x'},
          },
        }),
        {'uiFileDropPrompt': 'x'},
      );
    });

    test('keys that differ only by capitals stay apart', () {
      expect(
        flatten({
          'auth': {'logIn': 'Log In', 'login': 'Login'},
        }).keys,
        ['authLogIn', 'authLogin'],
      );
    });

    test('two keys that would make the same name fail', () {
      expect(
        () => flatten({
          'a': {'bC': 'x'},
          'aB': {'c': 'y'},
        }),
        throwsFormatException,
      );
    });
  });
}

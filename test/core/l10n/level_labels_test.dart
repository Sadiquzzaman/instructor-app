import 'package:flutter_test/flutter_test.dart';

import 'package:instructor_app/core/l10n/level_labels.dart';

/// Mirrors the web's frontend/i18n/levelLabels.test.ts.
void main() {
  const custom = LevelLabels(
    preset: 'CUSTOM',
    classLevel: LevelName(
      one: 'HSC Programme',
      other: 'HSC Programmes',
      bn: 'প্রোগ্রাম',
    ),
    sectionLevel: LevelName(one: 'Group', other: 'Groups', bn: 'গ্রুপ'),
  );

  test('fills each token with the right form and case', () {
    const l = LevelLabels.courseBatch;
    expect(l.word('class', 'en'), 'course');
    expect(l.word('Classes', 'en'), 'Courses');
    expect(l.word('sections', 'en'), 'batches');
    expect(l.word('Section', 'bn'), 'ব্যাচ');
  });

  test('keeps acronyms and capitalises custom words as needed', () {
    expect(custom.word('class', 'en'), 'HSC Programme');
    expect(custom.word('Section', 'en'), 'Group');
    expect(custom.word('sections', 'en'), 'groups');
  });

  test('replaces every token in a message', () {
    expect(
      custom.apply('All [[classes]] and [[Sections]]', 'en'),
      'All HSC Programmes and Groups',
    );
    expect(
      LevelLabels.defaults.apply('[[section]] of the [[class]]', 'bn'),
      'সেকশন of the ক্লাস',
    );
    expect(
      LevelLabels.defaults.apply('No tokens {count}', 'en'),
      'No tokens {count}',
    );
  });

  test('reads the API answer, falling back to Class / Section', () {
    expect(LevelLabels.fromJson(null), LevelLabels.defaults);
    expect(LevelLabels.fromJson({'preset': 'CUSTOM'}), LevelLabels.defaults);
    expect(
      LevelLabels.fromJson({'preset': 'COURSE_BATCH'}),
      LevelLabels.courseBatch,
    );
    expect(
      LevelLabels.fromJson({
        'preset': 'CUSTOM',
        'class': {
          'en': {'one': 'HSC Programme', 'other': 'HSC Programmes'},
          'bn': 'প্রোগ্রাম',
        },
        'section': {
          'en': {'one': 'Group', 'other': 'Groups'},
          'bn': 'গ্রুপ',
        },
      }),
      custom,
    );
    // A word over 30 characters is malformed.
    expect(
      LevelLabels.fromJson({
        'preset': 'CUSTOM',
        'class': {
          'en': {'one': 'x' * 31, 'other': 'y'},
          'bn': 'z',
        },
        'section': {
          'en': {'one': 'a', 'other': 'b'},
          'bn': 'c',
        },
      }),
      LevelLabels.defaults,
    );
  });
}

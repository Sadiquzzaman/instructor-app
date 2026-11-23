import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/time/clock.dart';
import 'package:instructor_app/features/ielts/data/attempts.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';
import 'ielts_overview_test.dart' show ieltsMember;

final _en = AppLocalizationsEn();

/// The fake's clock: the server says it is 10:00 and the module ends at
/// 10:20 (its deadline).
const _now = '2026-11-25T04:00:00.000Z';

Map<String, Object?> _opening({
  String purpose = 'PRACTICE',
  List<String> modules = const ['READING'],
  Map<String, Object?> attempts = const {},
  bool open = true,
}) => {
  'id': 'a1',
  'opens_at': '2026-11-25T03:00:00.000Z',
  'closes_at': '2026-11-29T03:00:00.000Z',
  'is_open': open,
  'test': {
    'id': 't1',
    'title': 'Reading set 1',
    'purpose': purpose,
    'test_type': 'ACADEMIC',
    'modules': modules,
    'durations': {
      'LISTENING': 1800,
      'READING': 1200,
      'WRITING': 3600,
      'SPEAKING': 840,
    },
  },
  'attempts': attempts,
};

Map<String, Object?> _attempt({
  String module = 'READING',
  String status = 'IN_PROGRESS',
  String purpose = 'PRACTICE',
  String deadline = '2026-11-25T04:20:00.000Z',
  Map<String, Object?> answers = const {},
  bool reviewed = false,
}) => {
  'attempt': {
    'id': 'x1',
    'assignment_id': 'a1',
    'module': module,
    'status': status,
    'deadline': deadline,
    'now': _now,
    'raw_score': status == 'IN_PROGRESS' ? null : 1,
    'raw_total': 2,
    'band': status == 'IN_PROGRESS' ? null : 5.5,
    'review_seconds': 0,
  },
  'test': {
    'id': 't1',
    'title': 'Reading set 1',
    'test_type': 'ACADEMIC',
    'purpose': purpose,
  },
  'parts': [
    if (module == 'READING')
      {
        'id': 'p1',
        'module': 'READING',
        'part_no': 1,
        'title': 'Bees',
        'content': '<p>Bees live in hives.</p>',
        'audio_file_id': null,
        'image_file_id': null,
        'groups': [
          {
            'id': 'g1',
            'type': 'TFNG',
            'instruction': 'Do the statements agree?',
            'word_limit': null,
            'shared': null,
            'image_file_id': null,
            'number_from': 1,
            'number_to': 2,
            'questions': [
              {
                'id': 'q1',
                'number_from': 1,
                'number_to': 1,
                'prompt': 'Bees live in hives.',
                'options': null,
                if (reviewed)
                  'key': {
                    'keys': ['TRUE'],
                  },
                if (reviewed) 'marks': 1,
              },
              {
                'id': 'q2',
                'number_from': 2,
                'number_to': 2,
                'prompt': 'Bees are fish.',
                'options': null,
                if (reviewed)
                  'key': {
                    'keys': ['FALSE'],
                  },
                if (reviewed) 'marks': 0,
              },
            ],
          },
        ],
      }
    else
      {
        'id': 'w1',
        'module': 'WRITING',
        'part_no': 1,
        'title': 'Task 1',
        'content': '<p>Describe the chart.</p>',
        'audio_file_id': null,
        'image_file_id': null,
        'groups': <Object>[],
      },
  ],
  'answers': answers,
};

FakeApi _api({
  List<Map<String, Object?>>? openings,
  Map<String, Object?>? attempt,
  FakeHandler? save,
}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on(
    'GET /me/entitlements',
    (_) => ok({
      'features': {'ielts': true},
    }),
  )
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /ielts/my/assignments', (_) => ok(openings ?? [_opening()]))
  ..on(
    'POST /ielts/my/assignments/a1/modules/READING/start',
    (_) => ok(_attempt()),
  )
  ..on('GET /ielts/my/attempts/x1', (_) => ok(attempt ?? _attempt()))
  ..on('PUT /ielts/my/attempts/x1/answers', save ?? (_) => ok(null))
  ..on(
    'POST /ielts/my/attempts/x1/submit',
    (_) => ok(_attempt(status: 'SUBMITTED', reviewed: true)),
  );

Future<void> _open(
  WidgetTester tester,
  FakeApi api,
  String route, {
  Size size = const Size(1000, 1600),
  String? lang,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: ieltsMember('STUDENT'),
    prefs: {'language': ?lang},
    overrides: [
      clockProvider.overrideWithValue(() => tester.binding.clock.now()),
    ],
  );
  app.read(routerProvider).go(route);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('rules', () {
    test('a mock waits for the earlier modules', () {
      final o = myOpeningsFromJson([
        _opening(
          purpose: 'MOCK',
          modules: ['LISTENING', 'READING', 'WRITING'],
          attempts: {
            'LISTENING': {'id': 'l', 'status': 'SUBMITTED'},
          },
        ),
      ]).single;
      expect(waitsForEarlier(o, 'LISTENING'), isFalse);
      expect(waitsForEarlier(o, 'READING'), isFalse);
      expect(waitsForEarlier(o, 'WRITING'), isTrue);
    });

    test('words count numbers too; Writing answers go by task', () {
      expect(essayWords(' The chart shows 3 lines. '), 5);
      expect(essayWords('   '), 0);
      expect(answerEntry('WRITING', 'w1', 'x'), {
        'part_id': 'w1',
        'answer': 'x',
      });
      expect(answerEntry('READING', 'q1', null), {
        'question_id': 'q1',
        'answer': null,
      });
    });
  });

  testWidgets('my tests: start Reading after the reminder', (tester) async {
    final api = _api();
    await _open(tester, api, '/ielts/my');
    expect(find.text('Reading set 1'), findsOneWidget);
    // The kind is a label, not something to press.
    expect(find.byKey(const Key('purpose-a1')), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
    await tester.tap(find.byKey(const Key('ielts-start-a1-READING')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(_en.ieltsTakeStartOther(20)), findsOneWidget);
    await tester.tap(find.byKey(const Key('ielts-start-confirm')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      api.to('POST /ielts/my/assignments/a1/modules/READING/start'),
      hasLength(1),
    );
  });

  testWidgets('my tests: a mock runs in order; Speaking with the teacher', (
    tester,
  ) async {
    await _open(
      tester,
      _api(
        openings: [
          _opening(
            purpose: 'MOCK',
            modules: ['LISTENING', 'READING', 'WRITING', 'SPEAKING'],
            attempts: {
              'READING': {'id': 'r', 'status': 'MARKED', 'band': 6.5},
            },
          ),
        ],
      ),
      '/ielts/my',
    );
    // Listening comes first in a mock and can start.
    expect(find.byKey(const Key('ielts-start-a1-LISTENING')), findsOneWidget);
    expect(find.text(_en.ieltsTakeBandShort('6.5')), findsOneWidget);
    expect(find.text(_en.ieltsTakeAfterPrevious), findsOneWidget);
    expect(find.text(_en.ieltsTakeWithTeacher), findsOneWidget);
  });

  testWidgets('reading: answers save after a moment; hand in', (tester) async {
    final api = _api();
    await _open(tester, api, '/ielts/attempts/x1');
    expect(find.text('Bees live in hives.'), findsWidgets);
    expect(find.text('20:00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('answer-q1-TRUE')));
    await tester.pump();
    expect(api.to('PUT /ielts/my/attempts/x1/answers'), isEmpty);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(api.to('PUT /ielts/my/attempts/x1/answers').single.body, {
      'answers': [
        {'question_id': 'q1', 'answer': 'TRUE'},
      ],
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(_en.ieltsTakeSaved), findsOneWidget);

    await tester.tap(find.byKey(const Key('flag-q2')));
    await tester.pump();
    expect(find.text(_en.ieltsTakeFlagged), findsOneWidget);

    await tester.tap(find.byKey(const Key('ielts-handin')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(_en.ieltsTakeHandInUnanswered(1)), findsOneWidget);
    await tester.tap(find.byKey(const Key('ielts-handin-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.to('POST /ielts/my/attempts/x1/submit').single.body, {
      'answers': [
        {'question_id': 'q1', 'answer': 'TRUE'},
      ],
    });
    // The result: score, band, and each answer with the right one.
    expect(find.text(_en.ieltsTakeScoreOutOf(1, 2)), findsOneWidget);
    expect(find.text('5.5'), findsOneWidget);
    expect(
      find.text('${_en.ieltsTakeWrong} · ${_en.ieltsTakeRightAnswer('FALSE')}'),
      findsOneWidget,
    );
  });

  testWidgets('at 0:00 the module is handed in by itself', (tester) async {
    final api = _api(attempt: _attempt(deadline: '2026-11-25T04:00:03.000Z'));
    await _open(tester, api, '/ielts/attempts/x1');
    expect(api.to('POST /ielts/my/attempts/x1/submit'), isEmpty);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.to('POST /ielts/my/attempts/x1/submit'), hasLength(1));
  });

  testWidgets('a save that fails is tried again', (tester) async {
    var calls = 0;
    final api = _api(
      save: (_) {
        calls++;
        return calls == 1 ? apiError(503) : ok(null);
      },
    );
    await _open(tester, api, '/ielts/attempts/x1');
    await tester.tap(find.byKey(const Key('answer-q1-FALSE')));
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(_en.ieltsTakeSaveFailed), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, 2);
    expect(find.text(_en.ieltsTakeSaved), findsOneWidget);
  });

  testWidgets('writing: the word count, saved by task', (tester) async {
    final api = _api(attempt: _attempt(module: 'WRITING'));
    await _open(tester, api, '/ielts/attempts/x1');
    expect(find.text('Describe the chart.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('writing-box-w1')),
      'The chart shows sales.',
    );
    await tester.pump();
    expect(
      find.text(
        '${_en.ieltsTakeWordCount(4)} · ${_en.ieltsTakeUnderMinimum(150)}',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 1600));
    expect(api.to('PUT /ielts/my/attempts/x1/answers').single.body, {
      'answers': [
        {'part_id': 'w1', 'answer': 'The chart shows sales.'},
      ],
    });
  });

  testWidgets('a mock on a phone asks for a tablet', (tester) async {
    await _open(
      tester,
      _api(attempt: _attempt(purpose: 'MOCK')),
      '/ielts/attempts/x1',
      size: const Size(400, 800),
    );
    expect(find.text(_en.ieltsTakeNeedComputer), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla: a practice set', (tester) async {
    final bn = AppLocalizationsBn();
    await _open(
      tester,
      _api(),
      '/ielts/attempts/x1',
      size: const Size(360, 780),
      lang: 'bn',
    );
    expect(find.text(bn.ieltsTakeHandIn), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

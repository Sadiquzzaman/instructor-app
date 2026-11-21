import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/time/clock.dart';
import 'package:instructor_app/features/ielts/screens/ielts_builder_screen.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

/// IELTS, end to end through the app's own screens against the in-process
/// fake API (Stage 5 plan, PR 13): staff make a practice set, add a
/// question group, publish it and open it for a batch; a student takes it
/// and hands it in; staff mark Writing. Run by `flutter test` (test/flows)
/// and on a device by `flutter test integration_test`.
void ieltsFlows() {
  testWidgets('staff: a practice set, a group, publish, open for a batch', (
    tester,
  ) async {
    final api = _centre();
    final c = await _signedIn(tester, api, 'TEACHER');
    await _go(tester, c, '/ielts/tests');
    await _tap(tester, find.byKey(const Key('ielts-test-new')));
    await tester.enterText(find.byKey(const Key('ielts-new-title')), 'Set 1');
    await tester.pump();
    await _tap(tester, find.byKey(const Key('ielts-new-purpose-PRACTICE')));
    await _tap(tester, find.byKey(const Key('ielts-new-create')));
    expect(api.to('POST /ielts/tests').single.body, {
      'title': 'Set 1',
      'test_type': 'ACADEMIC',
      'purpose': 'PRACTICE',
      'module': 'READING',
      'part_nos': [1],
    });
    expect(find.byType(IeltsBuilderScreen), findsOneWidget);

    await _tap(tester, find.byKey(const Key('group-add-p1')));
    await tester.tap(find.byKey(const Key('group-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('True / False / Not Given').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('group-instruction')),
      'Agree?',
    );
    await tester.enterText(
      find.byKey(const Key('question-prompt-0')),
      'Bees sleep.',
    );
    await _tap(tester, find.byKey(const Key('question-answer-0')));
    await tester.tap(find.text('NOT GIVEN').last);
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('group-save')));
    expect(api.to('POST /ielts/tests/t5/parts/p1/groups'), hasLength(1));

    // Back to the top of the builder, where the header is.
    await tester.fling(
      find.byType(NestedScrollView),
      const Offset(0, 2000),
      3000,
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('builder-publish')));
    expect(api.to('POST /ielts/tests/t5/publish'), hasLength(1));
    await _tap(tester, find.byKey(const Key('builder-openings')));
    await _tap(tester, find.byKey(const Key('opening-new')));
    await _tap(tester, find.byKey(const Key('opening-batch')));
    await tester.tap(find.text('Evening A').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('opening-save')), findsOneWidget);
  });

  testWidgets('a student takes Reading and hands it in', (tester) async {
    final api = _centre();
    final c = await _signedIn(tester, api, 'STUDENT');
    await _go(tester, c, '/ielts/my', settle: false);
    await tester.tap(find.byKey(const Key('ielts-start-a1-READING')));
    await _pumps(tester);
    await tester.tap(find.byKey(const Key('ielts-start-confirm')));
    await _pumps(tester);
    await tester.tap(find.byKey(const Key('answer-q1-TRUE')));
    await _pumps(tester);
    await tester.tap(find.byKey(const Key('ielts-handin')));
    await _pumps(tester);
    await tester.tap(find.byKey(const Key('ielts-handin-confirm')));
    await _pumps(tester);
    expect(api.to('POST /ielts/my/attempts/x1/submit').single.body, {
      'answers': [
        {'question_id': 'q1', 'answer': 'TRUE'},
      ],
    });
    expect(find.text('5.5'), findsOneWidget);
  });

  testWidgets('staff mark Writing from the list', (tester) async {
    final api = _centre();
    final c = await _signedIn(tester, api, 'TEACHER');
    await _go(tester, c, '/ielts/marking');
    await _tap(tester, find.byKey(const Key('marking-open-w9')));
    for (final k in ['TA', 'CC', 'LR', 'GRA']) {
      await _tap(tester, find.byKey(Key('criterion-k1-$k')));
      await tester.tap(find.text('6.0').last);
      await tester.pumpAndSettle();
    }
    await _tap(tester, find.byKey(const Key('writing-save')));
    expect(
      (api.to('PUT /ielts/marking/w9/writing').single.body! as Map)['tasks'],
      [
        {
          'part_id': 'k1',
          'criteria': {'TA': 6, 'CC': 6, 'LR': 6, 'GRA': 6},
        },
      ],
    );
  });
}

Future<void> _pumps(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<ProviderContainer> _signedIn(
  WidgetTester tester,
  FakeApi api,
  String role,
) {
  tester.view.physicalSize = const Size(1000, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final p = sessionPayload();
  return pumpInstructorApp(
    tester,
    api: api,
    session: Session.fromPayload({
      ...p,
      'id': 'me',
      'role': role == 'STUDENT' ? 'STUDENT' : 'TEACHER',
      'workspace_type': 'IELTS',
      'organization': <String, dynamic>{
        ...(p['organization'] as Map<String, dynamic>),
        'role': role,
        'workspace_type': 'IELTS',
      },
    }),
    overrides: [
      clockProvider.overrideWithValue(() => tester.binding.clock.now()),
    ],
  );
}

Future<void> _go(
  WidgetTester tester,
  ProviderContainer c,
  String route, {
  bool settle = true,
}) async {
  c.read(routerProvider).go(route);
  if (settle) {
    await tester.pumpAndSettle();
    await tester.pump(Duration.zero);
    await tester.pumpAndSettle();
  } else {
    await _pumps(tester);
  }
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      f,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Map<String, Object?> _test({String status = 'DRAFT', bool group = false}) => {
  'id': 't5',
  'title': 'Set 1',
  'purpose': 'PRACTICE',
  'test_type': 'ACADEMIC',
  'status': status,
  'modules': ['READING'],
  'durations': {'READING': 1200},
  'can_edit': true,
  'parts': [
    {
      'id': 'p1',
      'module': 'READING',
      'part_no': 1,
      'title': null,
      'content': null,
      'groups': [
        if (group)
          {
            'id': 'g1',
            'type': 'TFNG',
            'instruction': 'Agree?',
            'number_from': 1,
            'number_to': 1,
            'questions': [
              {
                'id': 'q1',
                'prompt': 'Bees sleep.',
                'answer': {
                  'keys': ['NOT GIVEN'],
                },
                'number_from': 1,
                'number_to': 1,
              },
            ],
          },
      ],
    },
  ],
};

Map<String, Object?> _attempt({String status = 'IN_PROGRESS'}) => {
  'attempt': {
    'id': 'x1',
    'module': 'READING',
    'status': status,
    'deadline': '2026-11-25T04:20:00.000Z',
    'now': '2026-11-25T04:00:00.000Z',
    'raw_score': status == 'IN_PROGRESS' ? null : 1,
    'raw_total': 1,
    'band': status == 'IN_PROGRESS' ? null : 5.5,
  },
  'test': {'id': 't5', 'title': 'Set 1', 'purpose': 'PRACTICE'},
  'parts': [
    {
      'id': 'p1',
      'module': 'READING',
      'part_no': 1,
      'content': '<p>Bees.</p>',
      'groups': [
        {
          'id': 'g1',
          'type': 'TFNG',
          'instruction': 'Agree?',
          'number_from': 1,
          'number_to': 1,
          'questions': [
            {
              'id': 'q1',
              'number_from': 1,
              'number_to': 1,
              'prompt': 'Bees sleep.',
            },
          ],
        },
      ],
    },
  ],
  'answers': <String, Object>{},
};

FakeApi _centre() {
  var published = false;
  var grouped = false;
  return FakeApi()
    ..on('GET /auth/contexts', (_) => ok(<Object>[]))
    ..on(
      'GET /me/entitlements',
      (_) => ok({
        'features': {'ielts': true},
      }),
    )
    ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
    ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
    ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
    ..on('GET /ielts/tests', (_) => ok(<Object>[]))
    ..on('GET /ielts/old-exams', (_) => ok(<Object>[]))
    ..on('POST /ielts/tests', (_) => ok({'id': 't5'}))
    ..on(
      'GET /ielts/tests/t5',
      (_) =>
          ok(_test(status: published ? 'PUBLISHED' : 'DRAFT', group: grouped)),
    )
    ..on('POST /ielts/tests/t5/parts/p1/groups', (_) {
      grouped = true;
      return ok(_test(group: true));
    })
    ..on('POST /ielts/tests/t5/publish', (_) {
      published = true;
      return ok(_test(status: 'PUBLISHED', group: true));
    })
    ..on('GET /ielts/tests/t5/assignments', (_) => ok(<Object>[]))
    ..on(
      'GET /sections',
      (_) => ok([
        {'id': 'sa', 'name': 'A', 'class_id': 'k1'},
      ]),
    )
    ..on(
      'GET /classes',
      (_) => ok([
        {'id': 'k1', 'class_name': 'Evening'},
      ]),
    )
    ..on(
      'GET /ielts/my/assignments',
      (_) => ok([
        {
          'id': 'a1',
          'opens_at': '2026-11-25T03:00:00.000Z',
          'closes_at': '2026-11-29T03:00:00.000Z',
          'is_open': true,
          'test': {
            'id': 't5',
            'title': 'Set 1',
            'purpose': 'PRACTICE',
            'modules': ['READING'],
            'durations': {'READING': 1200},
          },
          'attempts': <String, Object>{},
        },
      ]),
    )
    ..on(
      'POST /ielts/my/assignments/a1/modules/READING/start',
      (_) => ok(_attempt()),
    )
    ..on('GET /ielts/my/attempts/x1', (_) => ok(_attempt()))
    ..on('PUT /ielts/my/attempts/x1/answers', (_) => ok(null))
    ..on(
      'POST /ielts/my/attempts/x1/submit',
      (_) => ok(_attempt(status: 'SUBMITTED')),
    )
    ..on(
      'GET /ielts/marking',
      (_) => ok([
        {
          'attempt_id': 'w9',
          'module': 'WRITING',
          'status': 'SUBMITTED',
          'student': {'id': 's1', 'full_name': 'Tania Akter'},
          'test': {'id': 't6', 'title': 'Writing set'},
          'batch': 'Evening A',
          'submitted_at': '2026-11-25T05:00:00.000Z',
          'band': null,
        },
      ]),
    )
    ..on(
      'GET /ielts/marking/w9',
      (_) => ok({
        'attempt_id': 'w9',
        'module': 'WRITING',
        'status': 'SUBMITTED',
        'student': {'id': 's1', 'full_name': 'Tania Akter'},
        'test': {'id': 't6', 'title': 'Writing set'},
        'batch': 'Evening A',
        'band': null,
        'tasks': [
          {
            'part_id': 'k1',
            'part_no': 1,
            'content': '<p>Describe the chart.</p>',
            'script': 'The chart shows sales.',
            'words': 4,
            'min_words': 150,
          },
        ],
        'marks': <Object>[],
        'feedback': null,
      }),
    )
    ..on('PUT /ielts/marking/w9/writing', (_) => ok(null));
}

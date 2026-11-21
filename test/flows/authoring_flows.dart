import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/organization/screens/organization_overview_screen.dart';
import 'package:instructor_app/features/tests/screens/teacher_tests_screens.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

/// Authoring, end to end through the app's own screens against the
/// in-process fake API (Stage 4 plan, PR 8): set up a school, make and
/// publish a test, edit one. Run by `flutter test` (test/flows) and on a
/// device by `flutter test integration_test`.
void authoringFlows() {
  testWidgets('set up a school: a class, its section, finish', (tester) async {
    final api = _school();
    final c = await _signedIn(tester, api, 'OWNER');
    await _go(tester, c, '/organization/setup');

    await _tap(tester, find.byKey(const Key('setup-step-2')));
    await tester.enterText(
      find.byKey(const Key('setup-class-name')),
      'Class 7',
    );
    await tester.pump();
    await _tap(tester, find.byKey(const Key('setup-class-add')));
    expect(api.to('POST /classes').single.body, {'class_name': 'Class 7'});
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await _tap(tester, find.byKey(const Key('setup-step-3')));
    await tester.enterText(find.byKey(const Key('setup-section-name-c6')), 'A');
    await tester.pump();
    await _tap(tester, find.byKey(const Key('setup-section-add-c6')));
    expect(api.to('POST /classes/c6/sections').single.body, {
      'name': 'A',
      'session_id': 'se1',
    });
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await _tap(tester, find.byKey(const Key('setup-step-4')));
    await _tap(tester, find.byKey(const Key('setup-finish')));
    expect(api.to('POST /setup/complete'), hasLength(1));
    expect(find.byType(OrganizationOverviewScreen), findsOneWidget);
  });

  testWidgets('make a test: a choice and an essay, reordered, published', (
    tester,
  ) async {
    final api = _school();
    final c = await _signedIn(tester, api, 'TEACHER');
    await _go(tester, c, '/tests');
    await _tap(tester, find.byKey(const Key('tests-create')));

    await _type(tester, find.byKey(const Key('create-name')), 'Weekly quiz');
    await _tap(tester, find.byKey(const Key('create-class')));
    await tester.tap(find.text('Class 6').last);
    await tester.pumpAndSettle();
    await _type(tester, find.byKey(const Key('create-duration')), '30');
    await _tap(tester, find.byKey(const Key('create-next')));

    // A multiple-choice question.
    await _tap(tester, find.byKey(const Key('create-add-question')));
    await _type(tester, _prefixed('question-text-').first, 'What is 2 + 2?');
    final options = _prefixed('option-text-');
    for (final (i, v) in ['3', '4', '5'].indexed) {
      await _type(tester, options.at(i), v);
    }
    await _tap(tester, _prefixed('option-correct-', type: Checkbox).at(1));

    // An essay, marked by hand.
    await _tap(tester, find.byKey(const Key('create-category-ungraded')));
    await _tap(tester, find.byKey(const Key('create-add-question')));
    await _type(tester, _prefixed('question-text-').last, 'Describe a river.');

    await _tap(tester, find.byKey(const Key('create-next')));
    await _tap(tester, find.byKey(const Key('create-next')));
    // The essay first.
    await _tap(tester, find.byKey(const Key('order-down-0')));
    await _tap(tester, find.byKey(const Key('create-next')));
    await _tap(tester, find.byKey(const Key('create-publish')));

    final body = api.to('POST /exams').single.body! as Map;
    final qs = ((body['subjects'] as List).single as Map)['questions'] as List;
    expect(
      [for (final q in qs) (q as Map)['subType']],
      ['multiple-choice', 'essay'],
    );
    expect((qs[1] as Map)['type'], 'ungraded');
    expect(body['questionOrder'], [(qs[1] as Map)['id'], (qs[0] as Map)['id']]);
    expect((body['publishState'] as Map)['selectedClassId'], 'c6');
  });

  testWidgets('edit a test before it starts and save it', (tester) async {
    final api = _school();
    final c = await _signedIn(tester, api, 'TEACHER');
    await _go(tester, c, '/tests/e1');
    expect(find.byType(TeacherTestScreen), findsOneWidget);
    await _tap(tester, find.byKey(const Key('test-edit')));

    await _type(tester, find.byKey(const Key('create-name')), 'Algebra 2');
    for (var i = 0; i < 4; i++) {
      await _tap(tester, find.byKey(const Key('create-next')));
    }
    await _tap(tester, find.byKey(const Key('create-publish')));

    final body = api.to('PUT /exams/e1').single.body! as Map;
    expect((body['formState'] as Map)['testName'], 'Algebra 2');
    expect((body['publishState'] as Map)['scheduleAt'], _start);
    expect(find.byType(TeacherTestScreen), findsOneWidget);
  });
}

/// Far enough ahead that the test can still be edited.
const _start = '2099-01-01T04:00:00.000Z';

Finder _prefixed(String prefix, {Type type = TextField}) =>
    find.byWidgetPredicate(
      (w) =>
          w.runtimeType == type &&
          (w.key as ValueKey?)?.value.toString().startsWith(prefix) == true,
    );

Future<ProviderContainer> _signedIn(
  WidgetTester tester,
  FakeApi api,
  String role,
) {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final p = sessionPayload();
  return pumpInstructorApp(
    tester,
    api: api,
    session: Session.fromPayload({
      ...p,
      'id': 'me',
      'role': 'TEACHER',
      'organization': <String, dynamic>{
        ...(p['organization'] as Map<String, dynamic>),
        'role': role,
      },
    }),
  );
}

Future<void> _go(WidgetTester tester, ProviderContainer c, String route) async {
  c.read(routerProvider).go(route);
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

Future<void> _show(WidgetTester tester, Finder f) async {
  final scrollable = find.ancestor(of: f, matching: find.byType(Scrollable));
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      f,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  } else if (scrollable.evaluate().isNotEmpty) {
    await tester.ensureVisible(f);
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await _show(tester, f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, Finder f, String v) async {
  await _show(tester, f);
  await tester.enterText(f, v);
  await tester.pumpAndSettle();
}

Map<String, Object?> _exam() => {
  'id': 'e1',
  'test_name': 'Algebra',
  'exam_category': 'academic',
  'is_active': true,
  'status': 'pending',
  'created_by': 'me',
  'duration_minutes': 40,
  'exam_start_time': _start,
  'exam_end_time': '2099-01-01T05:00:00.000Z',
  'class_id': 'c6',
  'class_name': 'Class 6',
  'formState': {
    'testName': 'Algebra',
    'duration': 40,
    'passingScore': '',
    'allowNegativeMarking': false,
    'negativeMarking': '',
    'isModelTest': false,
    'examCategory': 'academic',
    'proctoring': {'level': 'LIGHT'},
  },
  'publishState': {
    'publishTiming': 'later',
    'scheduleAt': _start,
    'endingAt': '2099-01-01T05:00:00.000Z',
    'testAudience': 'selected_class',
    'selectedClassId': 'c6',
    'selectedOfferingId': '',
    'excluded_students': <Object>[],
  },
  'subjects': [
    {
      'id': 'm',
      'name': 'Mathematics',
      'questions': [
        {
          'id': 'q1',
          'type': 'graded',
          'subType': 'multiple-choice',
          'text': '<p>What is 2 + 2?</p>',
          'points': 1,
          'sortOrder': 0,
          'options': [
            {'id': 'o1', 'text': '3'},
            {'id': 'o2', 'text': '4'},
            {'id': 'o3', 'text': '5'},
          ],
          'answer': {
            'type': 'optionId',
            'value': ['o2'],
          },
        },
      ],
    },
  ],
};

FakeApi _school() => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on(
    'GET /me/entitlements',
    (_) => ok({
      'features': {'allow_ungraded_questions': true},
    }),
  )
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok({'preset': 'CLASS_SECTION'}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on('GET /sessions/closed', (_) => ok(<Object>[]))
  // The setup wizard.
  ..on(
    'GET /organizations/org-1',
    (_) => ok({'name': 'Demo School', 'status': 'approved'}),
  )
  ..on(
    'GET /organizations/org-1/settings',
    (_) => ok({
      'class_teacher_enabled': true,
      'branches_enabled': false,
      'guardians_enabled': false,
      'default_locale': 'bn',
      'sms_locale': 'bn',
    }),
  )
  ..on('PATCH /workspace/level-labels', (r) => ok(r.body))
  ..on(
    'GET /setup',
    (_) => ok({
      'setup_completed_at': null,
      'session': {'id': 'se1', 'name': '2026'},
      'classes': [
        {
          'id': 'c6',
          'name': 'Class 6',
          'subject_count': 1,
          'section_count': 1,
          'student_count': 0,
          'subjects_without_teacher': <Object>[],
        },
      ],
      'checkin_pin_missing': false,
    }),
  )
  ..on('POST /setup/complete', (_) => ok(null))
  ..on(
    'GET /sessions',
    (_) => ok([
      {
        'id': 'se1',
        'name': '2026',
        'start_date': '2026-01-01',
        'end_date': '2026-12-31',
        'status': 'ACTIVE',
        'is_default': true,
      },
    ]),
  )
  ..on('POST /classes', (_) => ok({'id': 'c7'}))
  ..on(
    'GET /classes/c6/subjects',
    (_) => ok([
      {
        'id': 'cs1',
        'subject_id': 'm',
        'subject': {'id': 'm', 'name': 'Mathematics'},
      },
    ]),
  )
  ..on(
    'GET /organizations/org-1/subjects',
    (_) => ok([
      {'id': 'm', 'name': 'Mathematics', 'code': 'M', 'classes': <Object>[]},
    ]),
  )
  ..on('GET /classes/c6/sections', (_) => ok(<Object>[]))
  ..on('POST /classes/c6/sections', (_) => ok({'id': 'sa'}))
  // Tests.
  ..on(
    'GET /classes',
    (_) => ok([
      {'id': 'c6', 'class_name': 'Class 6'},
    ]),
  )
  ..on(
    'GET /sections',
    (_) => ok([
      {'id': 'sa', 'name': 'A', 'class_id': 'c6'},
    ]),
  )
  ..on(
    'GET /offerings',
    (_) => ok([
      {
        'id': 'oa',
        'section_id': 'sa',
        'subject': {'id': 'm', 'name': 'Mathematics'},
        'teachers': [
          {'id': 'me', 'full_name': 'Rina'},
        ],
      },
    ]),
  )
  ..on(
    'GET /classes/c6/subjects/assigned',
    (_) => ok([
      {'subject_id': 'm', 'name': 'Mathematics', 'code': 'M'},
    ]),
  )
  ..on(
    'GET /exams/proctoring-options',
    (_) => ok({
      'levels': [
        {'level': 'OFF', 'available': true},
        {'level': 'LIGHT', 'available': true},
      ],
      'default_level': 'LIGHT',
    }),
  )
  ..on('POST /exams', (_) => ok({'id': 'e9'}))
  ..on('GET /exams/e9', (_) => ok({..._exam(), 'id': 'e9'}))
  ..on('GET /exams/e1', (_) => ok(_exam()))
  ..on('PUT /exams/e1', (_) => ok({'id': 'e1'}))
  ..on('GET /exams', (_) => ok(<Object>[]));

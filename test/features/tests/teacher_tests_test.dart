import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/tests/data/tests.dart';
import 'package:instructor_app/features/tests/screens/teacher_tests_screens.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Session _teacher() =>
    Session.fromPayload({...sessionPayload(), 'role': 'TEACHER'});

/// A test as `GET /exams` gives it to a teacher (checked on beta).
Map<String, Object?> _exam(
  String id,
  String name, {
  String status = 'pending',
  int active = 1,
  String start = '2099-01-01T04:00:00.000Z',
  String? session = 'se1',
}) => {
  'id': id,
  'test_name': name,
  'status': status,
  'is_active': active,
  'exam_category': 'ACADEMIC',
  'formState': {
    'testName': name,
    'duration': 40,
    'passingScore': '33',
    'allowNegativeMarking': true,
    'negativeMarking': '25',
  },
  'publishState': {
    'publishTiming': 'schedule',
    'scheduleAt': start,
    'endingAt': '2099-01-01T05:00:00.000Z',
    'testAudience': 'selectedClass',
    'excluded_students': <Object>[],
    'specificStudents': <Object>[],
  },
  'subjects': [
    {
      'id': 'sub1',
      'name': 'Mathematics',
      'code': 'MAT',
      'questions': [
        {'id': 'q1'},
        {
          'id': 'q2',
          'childQuestions': [
            {'id': 'c1'},
            {'id': 'c2'},
          ],
        },
      ],
    },
  ],
  'class_id': 'c1',
  'class_name': 'Class 6',
  'created_by': 'user-1',
  'session_id': session,
  'participant_count': 30,
  'submitted_count': 0,
};

FakeApi _api({FakeHandler? one, List<Object>? sessions}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /exams',
    (_) => ok([
      _exam('e1', 'Algebra quiz'),
      _exam('e2', 'Geometry final', status: 'completed'),
    ]),
  )
  ..on('GET /exams/e1', one ?? (_) => ok(_exam('e1', 'Algebra quiz')))
  ..on('PATCH /exams/e1/status', (_) => ok(<String, Object>{}))
  ..on('GET /sessions', (_) => ok(sessions ?? <Object>[]));

Future<void> _open(
  WidgetTester tester,
  FakeApi api,
  String route, {
  String? lang,
}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _teacher(),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go(route);
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

void main() {
  test('a teacher\'s test reads times, duration and questions', () {
    final t = TestItem.fromJson(_exam('e1', 'Algebra quiz'))!;
    expect(t.startsAt, DateTime.utc(2099, 1, 1, 4));
    expect(t.durationMinutes, 40);
    expect(t.subject, 'Mathematics');
    // A passage with two questions counts as two.
    expect(t.questionCount, 3);
    expect(t.negativeMarking, '25');
    expect(TestItem.fromJson(_exam('e1', 'x', active: 0))!.active, isFalse);
  });

  testWidgets('the list: by status, searchable; a test opens', (tester) async {
    await _open(tester, _api(), '/tests');
    expect(find.byType(TeacherTestsScreen), findsOneWidget);
    expect(find.byKey(const Key('test-e1')), findsOneWidget);
    expect(find.byKey(const Key('test-e2')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('tests-search')), 'geo');
    await tester.pump();
    expect(find.byKey(const Key('test-e1')), findsNothing);
    await tester.enterText(find.byKey(const Key('tests-search')), '');
    await tester.pump();
    // The filter chip (the card's status pill says "Completed" too).
    await tester.tap(find.widgetWithText(ChoiceChip, _en.testsFilterCompleted));
    await tester.pump();
    expect(find.byKey(const Key('test-e1')), findsNothing);
    await tester.tap(find.byKey(const Key('test-e2')));
    await tester.pumpAndSettle();
    expect(find.byType(TeacherTestScreen), findsOneWidget);
  });

  testWidgets('a test before it starts: facts; switch it off after asking', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, '/tests/e1');
    expect(find.text('Algebra quiz'), findsOneWidget);
    expect(find.text(_en.testsEnabled), findsOneWidget);
    // They made it (created_by is them): the live monitor is theirs.
    expect(find.byKey(const Key('test-monitor')), findsOneWidget);
    expect(find.text(_en.testsDetailsMinutes(40)), findsOneWidget);
    expect(find.text(_en.testsAudienceSelectedClass), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(_en.testsDetailsQuestionCount(3)),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('test-toggle')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('test-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('disable-confirm')));
    await tester.pumpAndSettle();
    expect(api.to('PATCH /exams/e1/status').single.body, {'active': false});
    expect(find.text(_en.testsDetailsStatusSaved), findsOneWidget);
  });

  testWidgets('a switched-off test is switched on without asking', (
    tester,
  ) async {
    final api = _api(one: (_) => ok(_exam('e1', 'Algebra quiz', active: 0)));
    await _open(tester, api, '/tests/e1');
    expect(find.text(_en.testsDisabled), findsOneWidget);
    await tester.tap(find.byKey(const Key('test-toggle')));
    await tester.pumpAndSettle();
    expect(api.to('PATCH /exams/e1/status').single.body, {'active': true});
  });

  testWidgets('started or in a closed session: no changes, says why', (
    tester,
  ) async {
    await _open(
      tester,
      _api(
        one: (_) =>
            ok(_exam('e1', 'Algebra quiz', start: '2020-01-01T04:00:00.000Z')),
      ),
      '/tests/e1',
    );
    expect(find.byKey(const Key('test-toggle')), findsNothing);
    expect(find.text(_en.testsDetailsLocked), findsOneWidget);
  });

  testWidgets('a closed session says so', (tester) async {
    await _open(
      tester,
      _api(
        sessions: [
          {'id': 'se1', 'status': 'CLOSED'},
        ],
      ),
      '/tests/e1',
    );
    expect(find.byKey(const Key('test-toggle')), findsNothing);
    expect(find.text(_en.testsDetailsSessionClosed), findsOneWidget);
  });

  testWidgets('a class\'s Tests tab lists its tests', (tester) async {
    final api = _api()
      ..on('GET /classes', (_) => ok(<Object>[]))
      ..on(
        'GET /classes/c1',
        (_) => ok({
          'id': 'c1',
          'class_name': 'Class 6',
          'classStudents': <Object>[],
        }),
      )
      ..on('GET /exams/class/c1', (_) => ok([_exam('e1', 'Algebra quiz')]));
    await _open(tester, api, '/classes/details/c1');
    await tester.tap(find.text(_en.classesTabsTests));
    await tester.pumpAndSettle();
    expect(api.to('GET /exams/class/c1'), hasLength(1));
    expect(find.byKey(const Key('test-e1')), findsOneWidget);
  });

  testWidgets('a completed test by another teacher: no live monitor', (
    tester,
  ) async {
    await _open(
      tester,
      _api(
        one: (_) => ok({
          ..._exam('e1', 'Algebra quiz', status: 'completed'),
          'created_by': 'someone-else',
        }),
      ),
      '/tests/e1',
    );
    expect(find.byKey(const Key('test-monitor')), findsNothing);
  });

  testWidgets('not theirs: not found', (tester) async {
    await _open(tester, _api(one: (_) => apiError(404)), '/tests/e1');
    expect(find.text(_en.testsDetailsNotFound), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), '/tests/e1', lang: 'bn');
    expect(find.text(bn.testsEnabled), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

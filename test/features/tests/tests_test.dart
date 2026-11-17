import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/tests/data/tests.dart';
import 'package:instructor_app/features/tests/screens/take_test_screen.dart';
import 'package:instructor_app/features/tests/screens/test_result_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Map<String, Object?> _test(
  String id,
  String status, {
  String name = 'Unit test',
}) => {
  'id': id,
  'test_name': name,
  'subject': 'Mathematics',
  'test_audience': 'selected_class',
  'duration_minutes': 30,
  'exam_start_time': '2026-11-18T04:00:00Z',
  'exam_end_time': '2026-11-18T05:00:00Z',
  'class_id': 'c1',
  'class_name': 'Class 6',
  'status': status,
  'participant_count': 4,
  'submitted_count': 1,
  'exam_category': 'ACADEMIC',
};

final _result = {
  'exam_id': 't3',
  'subject': 'Mathematics',
  'submitted_at': '2026-11-17T05:00:00Z',
  'status': 'SUBMITTED',
  'total_questions': 3,
  'correct_answers': 1,
  'wrong_answers': 1,
  'unanswered': 1,
  'total_score': 2,
  'max_score': 5,
  'percentage': 40,
  'grade': {'grade': 'C', 'gpa': 2},
  'questions': [
    {
      'question_id': 'q1',
      'type': 'graded',
      'question': '2 + 2 = ?',
      'instruction': '',
      'image_url': null,
      'points': 2,
      'sub_type': 'multiple-choice',
      'answer': {
        'type': 'optionId',
        'correct_answer': ['o4'],
        'student_selected': ['o4'],
      },
      'is_correct': true,
      'marks_obtained': 2,
      'options': [
        {'id': 'o3', 'text': 'Three'},
        {'id': 'o4', 'text': 'Four'},
      ],
    },
    {
      'id': 'p1',
      'type': 'passage-question',
      'passageText': 'The cat sat on the mat.',
      'childQuestions': [
        {
          'question_id': 'q2',
          'type': 'passage-question',
          'question': 'Where did the cat sit?',
          'points': 2,
          'answer': {
            'type': 'optionId',
            'correct_answer': ['m'],
            'student_selected': ['h'],
          },
          'is_correct': false,
          'marks_obtained': 0,
          'options': [
            {'id': 'm', 'text': 'On the mat'},
            {'id': 'h', 'text': 'On the hat'},
          ],
        },
      ],
    },
    {
      'question_id': 'q3',
      'type': 'graded',
      'question': 'Explain why.',
      'points': 1,
      'sub_type': 'essay',
      'answer': {'type': 'text', 'student_answer': ''},
      'is_correct': null,
      'marks_obtained': 0,
    },
  ],
  'submission': <String, Object>{},
  'totals': <String, Object>{},
};

FakeApi _api() => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /calendar/me', (_) => ok({'items': <Object>[]}))
  ..on(
    'GET /student/exams/assigned',
    (_) => ok([
      _test('t1', 'ongoing', name: 'Live quiz'),
      _test('t2', 'pending', name: 'Next week'),
      _test('t3', 'completed', name: 'Last month'),
    ]),
  )
  ..on('GET /student/exams/t3/result', (_) => ok(_result))
  ..on(
    'GET /student/exams/t9/result',
    (_) => apiError(403, message: 'Result has not been published yet'),
  )
  ..on(
    'GET /student/classes/c1',
    (_) => ok({'id': 'c1', 'class_name': 'Class 6', 'classmates': <Object>[]}),
  )
  ..on(
    'GET /student/exams/class/c1',
    (_) => ok([_test('t3', 'completed', name: 'Last month')]),
  );

Future<void> _open(WidgetTester tester, String route, {String? lang}) async {
  final c = await pumpInstructorApp(
    tester,
    api: _api(),
    session: testSession(),
    prefs: {'language': ?lang},
  );
  c.read(routerProvider).go(route);
  await tester.pumpAndSettle();
}

void main() {
  test('the answer sheet reads choices, passages and written answers', () {
    final r = TestResult.fromJson(_result);
    expect(r.questions, hasLength(3));
    expect(r.questions[0].studentAnswer, ['Four']);
    expect(r.questions[1].passage, 'The cat sat on the mat.');
    expect(r.questions[1].correctAnswer, ['On the mat']);
    expect(r.questions[2].studentAnswer, isEmpty);
    expect(r.grade, 'C');
  });

  testWidgets('tests by status; a finished one opens its result', (
    tester,
  ) async {
    await _open(tester, AppRoutes.tests);
    expect(find.text('Live quiz'), findsOneWidget);
    expect(find.text('Next week'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, _en.testsFilterCompleted));
    await tester.pumpAndSettle();
    expect(find.text('Live quiz'), findsNothing);
    await tester.tap(find.text(_en.testsCardResults));
    await tester.pumpAndSettle();
    expect(find.byType(TestResultScreen), findsOneWidget);
    expect(find.text('2/5'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(find.text(_en.appResultSummary(1, 1, 1)), findsOneWidget);
  });

  testWidgets('the answer sheet: right, wrong and not answered', (
    tester,
  ) async {
    await _open(tester, '${AppRoutes.tests}/t3/results');
    final scroll = find
        .descendant(
          of: find.byType(TestResultScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('result-q3')),
      200,
      scrollable: scroll,
    );
    expect(find.text('The cat sat on the mat.'), findsOneWidget);
    expect(find.text('On the hat'), findsOneWidget);
    expect(find.text('On the mat'), findsOneWidget);
    expect(find.text(_en.appResultIncorrect), findsOneWidget);
    expect(find.text(_en.appResultNoAnswer), findsWidgets);
    expect(find.text(_en.appResultMarks(0, 1)), findsOneWidget);
  });

  testWidgets('Start opens the test', (tester) async {
    await _open(tester, AppRoutes.tests);
    await tester.tap(find.text(_en.testsCardStart));
    await tester.pumpAndSettle();
    expect(find.byType(TakeTestScreen), findsOneWidget);
  });

  testWidgets('a class\'s Tests tab', (tester) async {
    await _open(tester, '${AppRoutes.classes}/details/c1');
    await tester.tap(find.text(_en.classesTabsTests));
    await tester.pumpAndSettle();
    expect(find.text('Last month'), findsOneWidget);
  });

  testWidgets('a result not published yet says so', (tester) async {
    await _open(tester, '${AppRoutes.tests}/t9/results');
    expect(find.text(_en.appResultNotPublished), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('in Bangla', (tester) async {
    final bn = AppLocalizationsBn();
    await _open(tester, AppRoutes.tests, lang: 'bn');
    expect(find.text(bn.testsStatusOngoing), findsWidgets);
  });
}

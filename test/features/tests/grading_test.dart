import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/tests/data/grading.dart';
import 'package:instructor_app/features/tests/screens/grading_screens.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Session _teacher() =>
    Session.fromPayload({...sessionPayload(), 'role': 'TEACHER'});

Map<String, Object?> _item(String id, String name, String status) => {
  'id': id,
  'test_name': name,
  'subject': 'Mathematics',
  'class_name': 'Class 6',
  'exam_end_time': '2026-11-17T05:00:00.000Z',
  'lifecycle_status': 'completed',
  'total_participants': 30,
  'submitted_count': 2,
  'graded_count': status == 'NEEDS_GRADING' ? 1 : 2,
  'pending_count': status == 'NEEDS_GRADING' ? 1 : 0,
  'average_percentage': 71.4,
  'has_manual_questions': true,
  'is_result_published': status == 'PUBLISHED',
  'result_published_at': null,
  'grading_status': status,
};

Map<String, Object?> _summary({int pending = 1, bool published = false}) => {
  'exam': {
    'id': 'e1',
    'test_name': 'Algebra final',
    'subject': 'Mathematics',
    'class_name': 'Class 6',
    'total_marks': 10,
    'has_manual_questions': true,
    'grading_status': pending > 0 ? 'NEEDS_GRADING' : 'GRADED',
    'is_result_published': published,
    'result_published_at': null,
  },
  'stats': {
    'total_students': 30,
    'submissions': 2,
    'not_submitted': 28,
    'graded': 2 - pending,
    'pending': pending,
  },
  'submissions': [
    {
      'submission_id': 'sub1',
      'student_id': 's1',
      'student_name': 'Karim Hasan',
      'email': 'karim@example.com',
      'submitted_at': '2026-11-17T04:50:00.000Z',
      'status': 'SUBMITTED',
      'total_score': 4,
      'max_score': 10,
      'is_graded': pending == 0,
      'grading_status': pending > 0 ? 'PENDING' : 'GRADED',
      'proctoring_summary': {'total_violations': 2},
    },
  ],
};

/// A submission: a choice question (auto) and a passage with a written one.
Map<String, Object?> _submission() => {
  'submission': {
    'submission_id': 'sub1',
    'student_name': 'Karim Hasan',
    'total_score': 4,
    'max_score': 10,
  },
  'totals': {
    'manual_total_count': 1,
    'manual_graded_count': 0,
    'auto_total_count': 1,
    'auto_graded_count': 1,
  },
  'questions': [
    {
      'question_id': 'q1',
      'question': 'What is 2 + 2?',
      'points': 4,
      'type': 'mcq',
      'options': [
        {'id': 'a', 'text': '3'},
        {'id': 'b', 'text': '4'},
      ],
      'answer': {
        'type': 'optionId',
        'correct_answer': ['b'],
        'student_selected': ['b'],
      },
      'is_correct': true,
      'marks_obtained': 4,
    },
    {
      'id': 'p1',
      'type': 'passage-question',
      'passageText': 'Read about Euclid.',
      'childQuestions': [
        {
          'question_id': 'q2',
          'question': 'Explain a proof.',
          'points': 6,
          'type': 'written',
          'answer': {'type': 'text', 'student_answer': 'Because of axioms.'},
          'is_correct': null,
          'marks_obtained': 0,
        },
      ],
    },
  ],
};

FakeApi _api({FakeHandler? summary}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /exams/grading/list',
    (r) => ok(
      r.query['status'] == 'PUBLISHED'
          ? <Object>[]
          : [
              _item('e1', 'Algebra final', 'NEEDS_GRADING'),
              _item('e2', 'Geometry quiz', 'GRADED'),
            ],
    ),
  )
  ..on('GET /exams/grading/e1', summary ?? (_) => ok(_summary()))
  ..on('GET /exams/grading/e1/submissions/sub1', (_) => ok(_submission()))
  ..on(
    'PATCH /exams/grading/e1/submissions/sub1',
    (_) => ok(<String, Object>{}),
  )
  ..on('POST /exams/grading/e1/publish', (_) => ok(<String, Object>{}));

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
  test('a passage\'s questions are read with their passage', () {
    final s = SubmissionForGrading.fromJson(_submission());
    expect(s.questions.map((q) => q.id), ['q1', 'q2']);
    expect(s.questions[1].manual, isTrue);
    expect(s.questions[1].passage, 'Read about Euclid.');
    expect(s.questions[0].manual, isFalse);
  });

  testWidgets('the list: tests to mark by status; one opens', (tester) async {
    final api = _api();
    await _open(tester, api, '/grading');
    expect(find.byType(GradingListScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('grading-e1')),
        matching: find.text(_en.gradingStatusNEEDSGRADING),
      ),
      findsOneWidget,
    );
    expect(find.textContaining(_en.gradingCardPending(1)), findsOneWidget);
    await tester.tap(find.byKey(const Key('grading-filter-PUBLISHED')));
    await tester.pumpAndSettle();
    expect(api.to('GET /exams/grading/list').last.query['status'], 'PUBLISHED');
    expect(find.text(_en.gradingEmpty), findsOneWidget);
    await tester.tap(find.byKey(const Key('grading-filter-ALL')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('grading-e1')));
    await tester.pumpAndSettle();
    expect(find.byType(GradingDetailScreen), findsOneWidget);
  });

  testWidgets('a test: counts, submissions; publish waits for all marked', (
    tester,
  ) async {
    await _open(tester, _api(), '/grading/details/e1');
    expect(find.text('Algebra final'), findsOneWidget);
    expect(find.text(_en.gradingSubmissionsGradeStatusPENDING), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('results-publish')))
          .onPressed,
      isNull,
    );
    expect(find.text(_en.gradingDetailsPublishHint), findsOneWidget);
  });

  testWidgets('all marked: publish results after asking', (tester) async {
    final api = _api(summary: (_) => ok(_summary(pending: 0)));
    await _open(tester, api, '/grading/details/e1');
    await tester.tap(find.byKey(const Key('results-publish')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('publish-confirm')));
    await tester.pumpAndSettle();
    expect(api.to('POST /exams/grading/e1/publish'), hasLength(1));
    expect(find.text(_en.gradingDetailsPublishedToast), findsOneWidget);
  });

  testWidgets('mark a written answer; marks above the points are refused', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, '/grading/details/e1');
    await tester.tap(find.byKey(const Key('submission-sub1')));
    await tester.pumpAndSettle();
    expect(find.text(_en.gradingAnswerCorrect), findsOneWidget);
    expect(find.text('Read about Euclid.'), findsOneWidget);
    expect(find.text('Because of axioms.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('marks-q2')), '7');
    await tester.pump();
    expect(find.text(_en.gradingAnswerAboveMax), findsOneWidget);
    await tester.enterText(find.byKey(const Key('marks-q2')), '5.5');
    await tester.enterText(
      find.byKey(const Key('feedback-q2')),
      ' Good start ',
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('grades-save')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('grades-save')));
    await tester.pumpAndSettle();
    expect(api.to('PATCH /exams/grading/e1/submissions/sub1').single.body, {
      'grades': [
        {
          'question_id': 'q2',
          'marks_obtained': 5.5,
          'explanation': 'Good start',
        },
      ],
    });
    // Back on the test, read again.
    expect(find.byType(GradingDetailScreen), findsOneWidget);
    expect(api.to('GET /exams/grading/e1'), hasLength(2));
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), '/grading/details/e1', lang: 'bn');
    expect(find.text(bn.gradingDetailsPublish), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

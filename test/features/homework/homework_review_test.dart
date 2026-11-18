import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/homework/data/homework_review.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Session _teacher() =>
    Session.fromPayload({...sessionPayload(), 'role': 'TEACHER'});

Map<String, Object?> _hw({String type = 'FILE', num? marks = 10}) => {
  'id': 'h1',
  'title': 'Chapter 3 exercise',
  'submission_type': type,
  'status': 'PUBLISHED',
  'subject': {'id': 'math', 'name': 'Mathematics'},
  'instructions': null,
  'total_marks': marks,
  'due_at': '2026-11-15T17:59:00.000Z',
  'attachments': <Object>[],
  'can_edit': true,
  'targets': [
    {
      'offering_id': 'o1',
      'section_label': 'Class 6 A',
      'student_ids': <String>[],
    },
  ],
  'student_count': 3,
  'publish_at': null,
};

Map<String, Object?> _score({
  num? raw,
  String? feedback,
  bool missing = false,
}) => {
  'raw_score': raw,
  'penalty': 0,
  'final_score': raw,
  'total_marks': 10,
  'percent': raw == null ? null : raw * 10,
  'grade': null,
  'feedback': feedback,
  'ratings': null,
  'is_missing': missing,
};

Map<String, Object?> _grid({
  num? marks = 10,
  bool published = false,
  Map<String, Object?>? s1Score,
}) => {
  'homework': {
    'id': 'h1',
    'total_marks': marks,
    'submission_type': 'FILE',
    'due_at': '2026-11-15T17:59:00.000Z',
    'scores_published_at': published ? '2026-11-17T04:00:00.000Z' : null,
  },
  'counts': {
    'students': 3,
    'handed_in': 2,
    'late': 1,
    'missing': 1,
    'scored': s1Score == null ? 0 : 1,
  },
  'rows': [
    {
      'student': {'id': 's1', 'full_name': 'Karim Hasan', 'roll_no': '1'},
      'latest': {
        'id': 'sub1',
        'version': 2,
        'submitted_at': '2026-11-14T10:00:00.000Z',
        'is_late': false,
        'late_minutes': null,
        'status': 'SUBMITTED',
      },
      'versions': 2,
      'score': s1Score,
    },
    {
      'student': {'id': 's2', 'full_name': 'Nadia Islam', 'roll_no': '2'},
      'latest': {
        'id': 'sub2',
        'version': 1,
        'submitted_at': '2026-11-16T10:00:00.000Z',
        'is_late': true,
        'late_minutes': 120,
        'status': 'SUBMITTED',
      },
      'versions': 1,
      'score': null,
    },
    {
      'student': {'id': 's3', 'full_name': 'Sami Rahman', 'roll_no': '3'},
      'latest': null,
      'versions': 0,
      'score': null,
    },
  ],
};

FakeApi _api({
  Map<String, Object?>? homework,
  FakeHandler? grid,
  FakeHandler? scores,
}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on('GET /homework', (_) => ok(<Object>[]))
  ..on('GET /homework/h1', (_) => ok(homework ?? _hw()))
  ..on('GET /homework/h1/grid', grid ?? (_) => ok(_grid()))
  ..on(
    'GET /homework/h1/submissions/sub1',
    (_) => ok({
      'versions': [
        {
          'id': 'sub0',
          'version': 1,
          'submitted_at': '2026-11-13T10:00:00.000Z',
          'is_late': false,
          'status': 'RETURNED',
          'text_answer': 'First try',
          'files': <Object>[],
        },
        {
          'id': 'sub1',
          'version': 2,
          'submitted_at': '2026-11-14T10:00:00.000Z',
          'is_late': false,
          'status': 'SUBMITTED',
          'text_answer': 'x = 4',
          'files': [
            {'id': 'f1', 'name': 'page1.jpg', 'mime': 'image/jpeg'},
          ],
        },
      ],
    }),
  )
  ..on(
    'PUT /homework/h1/scores',
    scores ?? (_) => ok(_grid(s1Score: _score(raw: 8, feedback: 'Good'))),
  )
  ..on('POST /homework/h1/submissions/sub1/return', (_) => ok(_grid()))
  ..on(
    'POST /homework/h1/publish-scores',
    (_) => ok(_grid(published: true, s1Score: _score(raw: 8))),
  )
  ..on(
    'POST /homework/h1/remind-missing',
    (_) => ok({'students': 1, 'guardian_sms': 1}),
  );

Future<void> _open(WidgetTester tester, FakeApi api, {String? lang}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _teacher(),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go('/homework/h1');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _settleSnack(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  group('scores (the web\'s rules)', () {
    test('scoreProblem: 0 to the total, two decimals at most', () {
      expect(scoreProblem('', 10), isFalse);
      expect(scoreProblem('8.5', 10), isFalse);
      expect(scoreProblem('8,25', 10), isFalse);
      expect(scoreProblem('11', 10), isTrue);
      expect(scoreProblem('-1', 10), isTrue);
      expect(scoreProblem('8.123', 10), isTrue);
      expect(scoreProblem('abc', 10), isTrue);
    });

    test('a draft as a row of PUT /scores', () {
      const d = ScoreDraft(
        raw: ' 8 ',
        feedback: ' Good ',
        ratings: {'effort': 4},
      );
      expect(d.toJson('s1', scored: true), {
        'student_id': 's1',
        'raw_score': 8,
        'feedback': 'Good',
        'is_missing': false,
        'ratings': {'effort': 4},
      });
      expect(
        const ScoreDraft(raw: '8', missing: true).toJson('s1', scored: true),
        containsPair('raw_score', null),
      );
      expect(
        const ScoreDraft().toJson('s1', scored: false).containsKey('raw_score'),
        isFalse,
      );
    });
  });

  testWidgets('counts, each student\'s state; open one and score it', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    await _scrollTo(tester, 'homework-review');
    expect(find.text(_en.homeworkSubmissionsSummary(2, 3)), findsOneWidget);
    expect(find.text(_en.homeworkSubmissionsNotPublished), findsOneWidget);
    await _scrollTo(tester, 'row-s3');
    expect(find.text(_en.homeworkMyWorkLate(120)), findsOneWidget);
    expect(find.text(_en.homeworkSubmissionsMissing), findsOneWidget);

    await _scrollTo(tester, 'row-s1');
    await tester.tap(find.byKey(const Key('row-s1')));
    await tester.pumpAndSettle();
    // Every version, newest first.
    expect(find.text('x = 4'), findsOneWidget);
    expect(find.text('First try'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('version-2'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('version-1'))).dy),
    );
    await tester.enterText(find.byKey(const Key('review-score')), '11');
    await tester.pump();
    expect(find.text(_en.homeworkSubmissionsScoreInvalid(10)), findsOneWidget);
    await tester.enterText(find.byKey(const Key('review-score')), '8');
    await tester.enterText(find.byKey(const Key('review-feedback')), 'Good');
    await tester.ensureVisible(find.byKey(const Key('review-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-save')));
    await tester.pumpAndSettle();
    expect(api.to('PUT /homework/h1/scores').single.body, {
      'rows': [
        {
          'student_id': 's1',
          'raw_score': 8,
          'feedback': 'Good',
          'is_missing': false,
          'ratings': null,
        },
      ],
    });
    // Back on the page with the new score.
    expect(find.textContaining('8/10'), findsOneWidget);
  });

  testWidgets('return for redo with a note', (tester) async {
    final api = _api();
    await _open(tester, api);
    await _scrollTo(tester, 'row-s1');
    await tester.tap(find.byKey(const Key('row-s1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('review-return')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-return')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('return-note')),
      ' Show working ',
    );
    await tester.tap(find.byKey(const Key('return-confirm')));
    await tester.pumpAndSettle();
    expect(api.to('POST /homework/h1/submissions/sub1/return').single.body, {
      'note': 'Show working',
    });
  });

  testWidgets('remind those missing (and their guardians); publish scores', (
    tester,
  ) async {
    final api = _api(grid: (_) => ok(_grid(s1Score: _score(raw: 8))));
    await _open(tester, api);
    await _scrollTo(tester, 'remind-missing');
    await tester.tap(find.byKey(const Key('remind-missing')));
    await tester.pumpAndSettle();
    expect(find.text(_en.homeworkSubmissionsRemindDetail(1)), findsOneWidget);
    await tester.tap(find.byKey(const Key('remind-sms')));
    await tester.tap(find.byKey(const Key('remind-send')));
    await tester.pumpAndSettle();
    expect(api.to('POST /homework/h1/remind-missing').single.body, {
      'sms_guardians': true,
    });
    expect(find.text(_en.homeworkSubmissionsReminded(1, 1)), findsOneWidget);
    await _settleSnack(tester);

    await _scrollTo(tester, 'publish-scores');
    await tester.tap(find.byKey(const Key('publish-scores')));
    await tester.pumpAndSettle();
    expect(
      find.text(_en.homeworkSubmissionsPublishDetail(1, 3)),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('publish-scores-confirm')));
    await tester.pumpAndSettle();
    expect(api.to('POST /homework/h1/publish-scores'), hasLength(1));
    expect(find.byKey(const Key('publish-scores')), findsNothing);
  });

  testWidgets('paper homework: a grid saved together, only changed rows', (
    tester,
  ) async {
    final api = _api(
      homework: _hw(type: 'PAPER'),
      scores: (_) => ok(_grid()),
    );
    await _open(tester, api);
    await _scrollTo(tester, 'paper-score-s1');
    await tester.enterText(find.byKey(const Key('paper-score-s1')), '7.5');
    await _scrollTo(tester, 'paper-missing-s3');
    await tester.tap(find.byKey(const Key('paper-missing-s3')));
    await tester.pumpAndSettle();
    expect(find.text(_en.homeworkSubmissionsUnsaved(2)), findsOneWidget);
    await _scrollTo(tester, 'paper-save');
    await tester.tap(find.byKey(const Key('paper-save')));
    await tester.pumpAndSettle();
    expect(api.to('PUT /homework/h1/scores').single.body, {
      'rows': [
        {
          'student_id': 's1',
          'raw_score': 7.5,
          'feedback': null,
          'is_missing': false,
          'ratings': null,
        },
        {
          'student_id': 's3',
          'raw_score': null,
          'feedback': null,
          'is_missing': true,
          'ratings': null,
        },
      ],
    });
  });

  testWidgets('a scoring refusal in the web\'s words', (tester) async {
    await _open(
      tester,
      _api(scores: (_) => apiError(409, code: 'HOMEWORK_NOT_LATEST')),
    );
    await _scrollTo(tester, 'row-s1');
    await tester.tap(find.byKey(const Key('row-s1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('review-score')), '8');
    await tester.ensureVisible(find.byKey(const Key('review-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-save')));
    await tester.pumpAndSettle();
    expect(find.text(_en.homeworkErrorsHOMEWORKNOTLATEST), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    await _scrollTo(tester, 'row-s3');
    expect(find.text(bn.homeworkSubmissionsTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

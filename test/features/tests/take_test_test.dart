import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/tests/data/exam_live.dart';
import 'package:instructor_app/features/tests/data/take_test.dart';
import 'package:instructor_app/features/tests/screens/take_test_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

class _Live implements ExamLive {
  final _events = StreamController<TeacherEvent>.broadcast();
  final joined = <String>[];
  final flags = <ProctorFlag>[];
  final submits = <Map<String, Object>>[];

  void send(TeacherEvent e) => _events.add(e);

  @override
  Stream<TeacherEvent> get events => _events.stream;
  @override
  void join(String examId) => joined.add(examId);
  @override
  void flag(String examId, ProctorFlag flag) => flags.add(flag);
  @override
  void submit(
    String examId, {
    required String studentId,
    required String studentName,
    required Map<String, Object> answers,
    required int totalFlagPoints,
  }) => submits.add(answers);
  @override
  void dispose() {}
}

Map<String, Object?> _eligibility({
  bool ok = true,
  String code = 'OK',
  String level = 'OFF',
  List<String> checks = const [],
  Map<String, Object?>? auto,
}) => {
  'eligible': ok,
  'can_access': ok,
  'reason_code': code,
  'proctoring': {
    'level': level,
    'checks': checks,
    'camera': level == 'STRICT',
    'auto_disqualify': auto,
  },
};

Map<String, Object?> _paper({int remaining = 1800, bool spoken = false}) => {
  'id': 'x1',
  'test_name': 'Unit test',
  'status': 'ongoing',
  'remaining_time_seconds': remaining,
  'subjects': [
    {
      'id': 's',
      'name': 'Maths',
      'questions': [
        {
          'id': 'q1',
          'type': 'graded',
          'subType': 'multiple-choice',
          'text': '2 + 2 = ?',
          'points': 1,
          'sortOrder': 1,
          'options': [
            {'id': 'a', 'text': 'Three'},
            {'id': 'b', 'text': 'Four'},
          ],
        },
        {
          'id': 'q2',
          'type': 'graded',
          'subType': 'multiple-response',
          'text': 'Even numbers?',
          'points': 2,
          'sortOrder': 2,
          'options': [
            {'id': 'c', 'text': 'Two'},
            {'id': 'd', 'text': 'Five'},
            {'id': 'e', 'text': 'Six'},
          ],
        },
        {
          'id': 'q3',
          'type': spoken ? 'ielts' : 'graded',
          'subType': spoken ? 'speaking-part-1' : 'essay',
          'text': 'Explain.',
          'points': 3,
          'sortOrder': 3,
        },
        {
          'id': 'p1',
          'type': 'passage-question',
          'passageText': 'The cat sat on the mat.',
          'sortOrder': 4,
          'childQuestions': [
            {
              'id': 'q4',
              'type': 'passage-question',
              'subType': 'matching-ordering',
              'text': 'Match.',
              'points': 2,
              'matchingOptions': {
                'left': [
                  {'id': 'l1', 'text': 'Cat'},
                ],
                'right': [
                  {'id': 'r1', 'text': 'Mat'},
                  {'id': 'r2', 'text': 'Hat'},
                ],
              },
            },
          ],
        },
      ],
    },
  ],
};

class _Api {
  _Api({
    Map<String, Object?>? eligibility,
    Map<String, Object?>? paper,
    this.submitFailures = 0,
  }) {
    api
      ..on('GET /auth/contexts', (_) => ok(<Object>[]))
      ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
      ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
      ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
      ..on('GET /calendar/me', (_) => ok({'items': <Object>[]}))
      ..on(
        'GET /student/exams/x1/eligibility',
        (_) => ok(eligibility ?? _eligibility()),
      )
      ..on(
        'POST /student/exams/x1/start',
        (_) => (
          201,
          {
            'statusCode': 201,
            'payload': {'id': 'att'},
          },
        ),
      )
      ..on('GET /exams/x1', (_) => ok(paper ?? _paper()))
      ..on('PUT /student/exams/x1/answersheet', (_) => ok(null))
      ..on('POST /student/exams/x1/report-violation', (_) => ok(null))
      ..on('POST /student/exams/x1/answersheet', (r) {
        if (submitFailures-- > 0) {
          throw DioException.connectionError(
            requestOptions: RequestOptions(path: r.path),
            reason: 'offline',
          );
        }
        return ok({'status': 'SUBMITTED'});
      });
  }

  final api = FakeApi();
  int submitFailures;
}

Future<(_Live, ProviderContainer)> _open(
  WidgetTester tester,
  FakeApi api, {
  Map<String, Object> prefs = const {},
}) async {
  final live = _Live();
  final c = await pumpInstructorApp(
    tester,
    api: api,
    session: testSession(),
    prefs: prefs,
    overrides: [examLiveProvider.overrideWithValue(live)],
  );
  c.read(routerProvider).go('${AppRoutes.tests}/x1/take');
  await tester.pumpAndSettle();
  return (live, c);
}

Future<void> _accept(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('accept-rules')));
  await tester.tap(find.byKey(const Key('accept-rules')));
  await tester.pump();
  await tester.ensureVisible(find.byKey(const Key('start-test')));
  await tester.tap(find.byKey(const Key('start-test')));
  await tester.pumpAndSettle();
}

Finder _scroll() => find
    .descendant(
      of: find.byType(TakeTestScreen),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _to(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: _scroll());
  await tester.pumpAndSettle();
}

/// Leaving the app and coming back, in the order Flutter reports it.
void _leaveAndCome(WidgetTester tester) {
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

/// Ends the screen so its timers stop.
Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 15));
}

void main() {
  test('the paper: order, passages, input modes; spoken answers', () {
    final p = TestPaper.fromJson(_paper());
    expect(p.questions.map((q) => q.id), ['q1', 'q2', 'q3', 'q4']);
    expect(p.questions.map((q) => q.mode), [
      'single-select',
      'multi-select',
      'text',
      'matching',
    ]);
    expect(p.questions.last.passage, 'The cat sat on the mat.');
    expect(p.totalMarks, 8);
    expect(TestPaper.fromJson(_paper(spoken: true)).hasSpokenAnswers, isTrue);
    expect(
      Eligibility.fromJson(_eligibility(level: 'STRICT')).needsComputer,
      isTrue,
    );
  });

  testWidgets('rules, answer every kind, saved, then submitted', (
    tester,
  ) async {
    final a = _Api();
    final (live, _) = await _open(tester, a.api);
    // Off: nothing is watched.
    expect(find.text(_en.examPermissionsWatchedNone), findsOneWidget);
    expect(find.text(_en.appTestRuleNoScreenshots), findsNothing);
    await _accept(tester);
    expect(a.api.to('POST /student/exams/x1/start'), hasLength(1));
    expect(live.joined, ['x1']);
    expect(find.byKey(const Key('time-left')), findsOneWidget);

    await tester.tap(find.byKey(const Key('choice-b')));
    await tester.pump();
    await _to(tester, find.byKey(const Key('choice-c')));
    await tester.tap(find.byKey(const Key('choice-c')));
    await tester.pump();
    await _to(tester, find.byKey(const Key('choice-e')));
    await tester.tap(find.byKey(const Key('choice-e')));
    await tester.pump();
    await _to(tester, find.byKey(const Key('answer-q3')));
    await tester.enterText(find.byKey(const Key('answer-q3')), 'Because.');
    await _to(tester, find.byKey(const Key('match-l1')));
    expect(find.text('The cat sat on the mat.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('match-l1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mat').last);
    await tester.pumpAndSettle();

    // Sent a few seconds after the last change: only what changed.
    await tester.pump(saveAfter);
    await tester.pumpAndSettle();
    final saved = a.api.to('PUT /student/exams/x1/answersheet');
    expect(saved, isNotEmpty);
    expect(
      (saved.last.body! as Map)['answersheet'],
      containsPair('q4', ['l1::r1']),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('progress')),
      -300,
      scrollable: _scroll(),
    );
    expect(find.text(_en.examNavigatorProgress(4, 4)), findsOneWidget);

    await _to(tester, find.byKey(const Key('submit-test')));
    await tester.tap(find.byKey(const Key('submit-test')));
    await tester.pumpAndSettle();
    expect(find.text(_en.examSubmitDetail(0)), findsOneWidget);
    await tester.tap(find.text(_en.examSubmitConfirm));
    await tester.pumpAndSettle();
    final body =
        a.api.to('POST /student/exams/x1/answersheet').single.body! as Map;
    expect(body['reason'], 'manual');
    expect(body['studentId'], 'user-1');
    expect(body['answersheet'], {
      'q1': ['b'],
      'q2': ['c', 'e'],
      'q3': 'Because.',
      'q4': ['l1::r1'],
    });
    expect(live.submits, hasLength(1));
    expect(find.text(_en.examMessageAlreadySubmittedTitle), findsOneWidget);
    await _end(tester);
  });

  testWidgets('strict tests need a computer; nothing is started', (
    tester,
  ) async {
    final a = _Api(eligibility: _eligibility(level: 'STRICT'));
    await _open(tester, a.api);
    expect(find.text(_en.appTestUseComputer), findsOneWidget);
    expect(a.api.to('POST /student/exams/x1/start'), isEmpty);
  });

  testWidgets('a test that has not started says so', (tester) async {
    await _open(
      tester,
      _Api(eligibility: _eligibility(ok: false, code: 'NOT_STARTED')).api,
    );
    expect(find.text(_en.examMessageNotStartedTitle), findsOneWidget);
  });

  testWidgets('time up: submitted by itself', (tester) async {
    final a = _Api(paper: _paper(remaining: 2));
    await _open(tester, a.api);
    await _accept(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(
      (a.api.to('POST /student/exams/x1/answersheet').single.body!
          as Map)['reason'],
      'timeout',
    );
    expect(find.text(_en.examMessageTimeUpTitle), findsOneWidget);
    await _end(tester);
  });

  testWidgets('light: leaving the app is flagged; at the limit the test ends', (
    tester,
  ) async {
    final a = _Api(
      eligibility: _eligibility(
        level: 'LIGHT',
        checks: ['proctoring_tab_switch', 'proctoring_copy_paste'],
        auto: {
          'threshold': 2,
          'warn_at': 1,
          'checks': ['proctoring_tab_switch'],
        },
      ),
    );
    final (live, _) = await _open(tester, a.api);
    expect(find.text(_en.appTestRuleLeaveApp), findsOneWidget);
    expect(find.text(_en.examPermissionsRulesLimit(2)), findsOneWidget);
    await _accept(tester);

    _leaveAndCome(tester);
    await tester.pumpAndSettle();
    expect(live.flags.single.type, 'tab-switch');
    expect(a.api.to('POST /student/exams/x1/report-violation').single.body, {
      'violation_type': 'TAB_SWITCH',
    });
    expect(find.byKey(const Key('flag-warning')), findsOneWidget);

    _leaveAndCome(tester);
    await tester.pumpAndSettle();
    final body =
        a.api.to('POST /student/exams/x1/answersheet').single.body! as Map;
    expect(body['reason'], 'disqualified');
    expect((body['proctoring_events']! as List), hasLength(2));
    expect(find.text(_en.examMessageDisqualifiedTitle), findsOneWidget);
    await _end(tester);
  });

  testWidgets('the teacher ends the test', (tester) async {
    final a = _Api();
    final (live, _) = await _open(tester, a.api);
    await _accept(tester);
    live.send(TestEnded('Phone on desk'));
    await tester.pumpAndSettle();
    final body =
        a.api.to('POST /student/exams/x1/answersheet').single.body! as Map;
    expect(body['disqualification_reason'], 'Phone on desk');
    expect(find.text(_en.examEndedByTeacher('Phone on desk')), findsOneWidget);
    await _end(tester);
  });

  testWidgets('no connection at submit: tried again until it goes', (
    tester,
  ) async {
    final a = _Api(submitFailures: 1);
    await _open(tester, a.api);
    await _accept(tester);
    await _to(tester, find.byKey(const Key('submit-test')));
    await tester.tap(find.byKey(const Key('submit-test')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.examSubmitConfirm));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text(_en.examSubmitWaitingTitle), findsOneWidget);
    await tester.pump(submitRetryEvery);
    await tester.pumpAndSettle();
    expect(a.api.to('POST /student/exams/x1/answersheet'), hasLength(2));
    expect(find.text(_en.examMessageAlreadySubmittedTitle), findsOneWidget);
    await _end(tester);
  });

  testWidgets('answers kept on the phone come back', (tester) async {
    await _open(
      tester,
      _Api().api,
      prefs: {
        'exam/user-1/x1': jsonEncode({
          'q1': ['a'],
          'q3': 'Draft',
        }),
      },
    );
    await _accept(tester);
    expect(find.text(_en.examNavigatorProgress(2, 4)), findsOneWidget);
    await _to(tester, find.byKey(const Key('answer-q3')));
    expect(find.text('Draft'), findsOneWidget);
    await _end(tester);
  });
}

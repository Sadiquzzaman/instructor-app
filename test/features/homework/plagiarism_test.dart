import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/homework/data/plagiarism.dart';
import 'package:instructor_app/features/homework/screens/plagiarism_screens.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Session _teacher() =>
    Session.fromPayload({...sessionPayload(), 'role': 'TEACHER'});

Map<String, Object?> _p(String id, String name) => {
  'id': id,
  'full_name': name,
};

Map<String, Object?> _report({bool ran = true, String? decision}) => {
  'check': ran
      ? {
          'id': 'c1',
          'ran_at': '2026-11-17T04:00:00.000Z',
          'ran_by': null,
          'submissions': 3,
        }
      : null,
  'thresholds': {'high': 40, 'medium': 20, 'min_words': 50},
  'submissions': [
    {
      'submission_id': 'sub1',
      'student': _p('s1', 'Karim Hasan'),
      'part_no': null,
      'words': 120,
      'not_checked': null,
      'percent': 62,
      'level': 'HIGH',
      'most_similar': [
        {'match_id': 'm1', 'student': _p('s2', 'Nadia Islam'), 'percent': 62},
      ],
    },
    {
      'submission_id': 'sub3',
      'student': _p('s3', 'Sami Rahman'),
      'part_no': null,
      'words': 12,
      'not_checked': 'TOO_SHORT',
      'percent': 0,
      'level': null,
      'most_similar': <Object>[],
    },
  ],
  'matches': [
    {
      'id': 'm1',
      'part_no': null,
      'a': {'student': _p('s1', 'Karim Hasan'), 'percent': 62},
      'b': {'student': _p('s2', 'Nadia Islam'), 'percent': 58},
      'score': 60,
      'level': 'HIGH',
      'review_decision': decision,
      'review_note': null,
    },
    {
      'id': 'm2',
      'part_no': null,
      'a': {'student': _p('s1', 'Karim Hasan'), 'percent': 5},
      'b': {'student': _p('s3', 'Sami Rahman'), 'percent': 5},
      'score': 5,
      'level': 'LOW',
      'review_decision': null,
      'review_note': null,
    },
  ],
};

Map<String, Object?> _match({String? decision, String? note}) => {
  'id': 'm1',
  'part_no': null,
  'level': 'HIGH',
  'score': 60,
  'a': {
    'student': _p('s1', 'Karim Hasan'),
    'text': 'The cat sat on the mat today.',
    'spans': [
      {'start': 4, 'end': 15},
    ],
    'percent': 62,
  },
  'b': {
    'student': _p('s2', 'Nadia Islam'),
    'text': 'A cat sat on the mat.',
    'spans': [
      {'start': 2, 'end': 13},
    ],
    'percent': 58,
  },
  'review_decision': decision,
  'review_note': note,
  'reviewed_by': null,
  'reviewed_at': decision == null ? null : '2026-11-18T04:00:00.000Z',
};

FakeApi _api({FakeHandler? latest}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on('GET /homework', (_) => ok(<Object>[]))
  ..on(
    'GET /homework/h1',
    (_) => ok({
      'id': 'h1',
      'title': 'Essay',
      'submission_type': 'TEXT',
      'status': 'PUBLISHED',
      'subject': {'id': 'e', 'name': 'English'},
      'attachments': <Object>[],
      'can_edit': true,
      'targets': <Object>[],
      'student_count': 3,
    }),
  )
  ..on('GET /homework/h1/grid', (_) => ok({'rows': <Object>[]}))
  ..on('GET /integrity/checks/latest', latest ?? (_) => ok(_report()))
  ..on('POST /integrity/checks', (_) => ok(_report()))
  ..on('GET /integrity/matches/m1', (_) => ok(_match()))
  ..on(
    'PUT /integrity/matches/m1/review',
    (_) => ok(_match(decision: 'COPIED', note: 'Same wording')),
  );

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
  test('markedPieces cuts a text at the shared passages', () {
    expect(markedPieces('The cat sat.', [(start: 4, end: 7)]), [
      (text: 'The ', marked: false),
      (text: 'cat', marked: true),
      (text: ' sat.', marked: false),
    ]);
    // Spans out of range are kept inside the text.
    expect(markedPieces('abc', [(start: 1, end: 9)]).last, (
      text: 'bc',
      marked: true,
    ));
  });

  testWidgets('a published homework opens its plagiarism check', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, '/homework/h1');
    await tester.tap(find.byKey(const Key('homework-plagiarism')));
    await tester.pumpAndSettle();
    expect(find.byType(SimilarityScreen), findsOneWidget);
    expect(api.to('GET /integrity/checks/latest').single.query, {
      'scope_type': 'HOMEWORK',
      'scope_id': 'h1',
    });
  });

  testWidgets('the report: each hand-in, pairs at Medium or High; run now', (
    tester,
  ) async {
    final api = _api(latest: (_) => ok(_report(ran: false)));
    await _open(tester, api, '/homework/h1/similarity');
    expect(find.text(_en.plagiarismTitle('Essay')), findsOneWidget);
    expect(find.textContaining(_en.plagiarismNotRunYet), findsOneWidget);
    expect(find.text('${_en.plagiarismLevelsHIGH} · 62%'), findsOneWidget);
    expect(find.text(_en.plagiarismNotCheckedTOOSHORT), findsOneWidget);
    // The report's own list, not whichever scrollable the shell builds first.
    final list = find.descendant(
      of: find.byType(SimilarityScreen),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('pair-m1')),
      200,
      scrollable: list.first,
    );
    // A Low pair nobody reviewed is left out.
    expect(find.byKey(const Key('pair-m2')), findsNothing);
    expect(find.text(_en.plagiarismNotReviewed), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('plagiarism-run')),
      -200,
      scrollable: list.first,
    );
    await tester.tap(find.byKey(const Key('plagiarism-run')));
    await tester.pumpAndSettle();
    expect(api.to('POST /integrity/checks').single.body, {
      'scope_type': 'HOMEWORK',
      'scope_id': 'h1',
    });
    expect(find.text(_en.plagiarismRan), findsOneWidget);
    expect(find.textContaining(_en.plagiarismNotRunYet), findsNothing);
    // Let the "Check finished" note go before the test ends.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('a match: both texts marked; review as copied with a note', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, '/homework/h1/similarity');
    await tester.tap(find.byKey(const Key('compare-m1')));
    await tester.pumpAndSettle();
    expect(find.byType(MatchScreen), findsOneWidget);
    expect(
      find.text(_en.plagiarismMatchTitle('Karim Hasan', 'Nadia Islam')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('side-s1')), findsOneWidget);
    expect(find.byKey(const Key('side-s2')), findsOneWidget);
    // Save waits for a decision.
    await tester.scrollUntilVisible(
      find.byKey(const Key('review-save')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('review-save')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('decision-COPIED')));
    await tester.enterText(
      find.byKey(const Key('review-note')),
      ' Same wording ',
    );
    await tester.tap(find.byKey(const Key('review-save')));
    await tester.pumpAndSettle();
    expect(api.to('PUT /integrity/matches/m1/review').single.body, {
      'decision': 'COPIED',
      'note': 'Same wording',
    });
    expect(find.text(_en.plagiarismReviewSaved), findsOneWidget);
  });

  testWidgets('not in the plan says so', (tester) async {
    await _open(
      tester,
      _api(
        latest: (_) =>
            apiError(403, code: 'FEATURE_NOT_IN_PLAN', feature: 'integrity'),
      ),
      '/homework/h1/similarity',
    );
    expect(find.text(_en.plagiarismNotAvailable), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla: the texts one above the other', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), '/integrity/matches/m1', lang: 'bn');
    expect(
      find.text(bn.plagiarismMatchTitle('Karim Hasan', 'Nadia Islam')),
      findsOneWidget,
    );
    final a = tester.getTopLeft(find.byKey(const Key('side-s1')));
    final b = tester.getTopLeft(find.byKey(const Key('side-s2')));
    expect(a.dx, b.dx);
    expect(a.dy, lessThan(b.dy));
    expect(tester.takeException(), isNull);
  });
}

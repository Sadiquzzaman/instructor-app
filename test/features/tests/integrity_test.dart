import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/tests/screens/integrity_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Session _teacher() =>
    Session.fromPayload({...sessionPayload(), 'role': 'TEACHER'});

Map<String, Object?> _row(
  String id,
  String name,
  String status, {
  int flags = 0,
  String? decision,
}) => {
  'student_id': id,
  'student_name': name,
  'status': status,
  'total_score': status == 'IN_PROGRESS' ? null : 7,
  'max_score': 10,
  'flags': flags,
  'checks': flags == 0
      ? <Object>[]
      : [
          {'check': 'proctoring_tab_switch', 'count': flags},
        ],
  'disqualification_reason': status == 'DISQUALIFIED' ? 'Too many flags' : null,
  'last_review': decision == null
      ? null
      : {
          'decision': decision,
          'reason': 'ok',
          'decided_at': '2026-11-18T04:00:00.000Z',
        },
};

FakeApi _api({FakeHandler? report}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on('GET /exams', (_) => ok(<Object>[]))
  ..on('GET /exams/e1', (_) => ok({'id': 'e1', 'test_name': 'Algebra quiz'}))
  ..on(
    'GET /exams/e1/proctoring/integrity',
    report ??
        (_) => ok({
          'exam_id': 'e1',
          'summary': {
            'students': 3,
            'flagged': 1,
            'disqualified': 1,
            'reviewed': 1,
          },
          'by_check': [
            {'check': 'proctoring_tab_switch', 'count': 6, 'students': 1},
            {'check': 'made_up_check', 'count': 1, 'students': 1},
          ],
          'students': [
            _row('s1', 'Karim Hasan', 'DISQUALIFIED', flags: 6),
            _row('s2', 'Nadia Islam', 'SUBMITTED', decision: 'CONFIRM'),
            _row('s3', 'Sami Rahman', 'IN_PROGRESS'),
          ],
        }),
  )
  ..on(
    'GET /exams/e1/proctoring/students/s1/report',
    (_) => ok({
      'attempt': {
        'student_id': 's1',
        'student_name': 'Karim Hasan',
        'status': 'DISQUALIFIED',
        'total_score': 7,
        'max_score': 10,
        'disqualification_reason': 'Too many flags',
      },
      'checks': [
        {'check': 'proctoring_tab_switch', 'count': 6},
      ],
      'timeline': [
        {
          'id': 'ev1',
          'type': 'tab-switch',
          'occurred_at': '2026-11-18T04:00:00.000Z',
          'source': 'CLIENT',
        },
      ],
      'reviews': [
        {
          'id': 'rv1',
          'decision': 'CONFIRM',
          'reason': 'Seen on camera',
          'previous_status': 'DISQUALIFIED',
          'previous_score': 7,
          'decided_at': '2026-11-18T05:00:00.000Z',
          'decided_by_name': 'Rina Akter',
        },
      ],
    }),
  )
  ..on(
    'GET /exams/e1/proctoring/students/s3/report',
    (_) => ok({
      'attempt': {'status': 'IN_PROGRESS'},
      'checks': <Object>[],
      'timeline': <Object>[],
      'reviews': <Object>[],
    }),
  )
  ..on(
    'POST /exams/e1/proctoring/students/s1/review',
    (_) => ok(<String, Object>{}),
  );

Future<void> _open(WidgetTester tester, FakeApi api, {String? lang}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _teacher(),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go('/tests/e1/integrity');
  await tester.pumpAndSettle();
  // The tests list under this page answers a tick later.
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

Finder _scrollable() => find.byType(Scrollable).first;

void main() {
  testWidgets('summary, flags by check, each student most flagged first', (
    tester,
  ) async {
    await _open(tester, _api());
    expect(find.byType(IntegrityScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('integrity-s1')),
        matching: find.text(_en.integrityStatusDISQUALIFIED),
      ),
      findsOneWidget,
    );
    expect(find.text(_en.featuresCatalogProctoringTabSwitchName), findsWidgets);
    // A check not in the plan catalogue is "Other".
    expect(find.text(_en.integrityOtherCheck), findsOneWidget);
    expect(find.text(_en.integrityCheckCount(6, 1)), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('integrity-s3')),
      200,
      scrollable: _scrollable(),
    );
    expect(find.textContaining(_en.integrityDecisionCONFIRM), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('integrity-s1'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('integrity-s2'))).dy),
    );
  });

  testWidgets('a disqualified student: report, history; reinstate with a '
      'reason', (tester) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('integrity-s1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Too many flags'), findsOneWidget);
    expect(find.text(_en.monitorEventsTabSwitch), findsOneWidget);
    expect(
      find.text(_en.integrityDecidedBy('Rina Akter', 'Seen on camera')),
      findsOneWidget,
    );
    // Reinstating is offered only to a disqualified student.
    await tester.scrollUntilVisible(
      find.byKey(const Key('decision-REINSTATE')),
      200,
      scrollable: _scrollable(),
    );
    await tester.tap(find.byKey(const Key('decision-REINSTATE')));
    await tester.pump();
    final save = find.byKey(const Key('integrity-save'));
    await tester.scrollUntilVisible(save, 200, scrollable: _scrollable());
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('integrity-reason')),
      ' Flags were a broken camera ',
    );
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(api.to('POST /exams/e1/proctoring/students/s1/review').single.body, {
      'decision': 'REINSTATE',
      'reason': 'Flags were a broken camera',
    });
    expect(find.text(_en.integritySaved), findsOneWidget);
  });

  testWidgets('still writing: no decision yet', (tester) async {
    await _open(tester, _api());
    await tester.scrollUntilVisible(
      find.byKey(const Key('integrity-s3')),
      200,
      scrollable: _scrollable(),
    );
    await tester.tap(find.byKey(const Key('integrity-s3')));
    await tester.pumpAndSettle();
    expect(find.text(_en.integrityWriting), findsOneWidget);
    expect(find.byKey(const Key('integrity-save')), findsNothing);
  });

  testWidgets('not allowed says so', (tester) async {
    await _open(tester, _api(report: (_) => apiError(403)));
    expect(find.text(_en.integrityNotAllowed), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.integrityTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

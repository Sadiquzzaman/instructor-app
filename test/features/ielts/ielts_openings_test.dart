import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/widgets/date_time_field.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';
import 'ielts_overview_test.dart' show ieltsMember;

final _en = AppLocalizationsEn();

FakeApi _api({String status = 'PUBLISHED'}) => FakeApi()
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
  ..on(
    'GET /ielts/tests/t1',
    (_) => ok({
      'id': 't1',
      'title': 'Full mock 1',
      'purpose': 'MOCK',
      'test_type': 'ACADEMIC',
      'status': status,
      'modules': ['LISTENING', 'READING', 'WRITING', 'SPEAKING'],
      'durations': <String, Object>{},
      'can_edit': true,
      'parts': <Object>[],
    }),
  )
  ..on(
    'GET /ielts/tests/t1/assignments',
    (_) => ok([
      {
        'id': 'a1',
        'section': {'id': 'sa', 'name': 'Evening A'},
        'opens_at': '2026-11-25T03:00:00.000Z',
        'closes_at': '2026-11-25T11:00:00.000Z',
        'students': 12,
        'submitted': {'LISTENING': 10, 'READING': 9},
      },
    ]),
  )
  ..on(
    'GET /ielts/assignments/a1/results',
    (_) => ok([
      {
        'student': {'id': 's1', 'full_name': 'Tania Akter'},
        'modules': {
          'LISTENING': {
            'attempt_id': 'x1',
            'status': 'MARKED',
            'band': 7,
            'raw_score': 31,
            'raw_total': 40,
          },
          'READING': {'attempt_id': 'x2', 'status': 'IN_PROGRESS'},
          'WRITING': {'attempt_id': 'x3', 'status': 'SUBMITTED', 'band': null},
        },
        'overall': null,
      },
    ]),
  )
  ..on(
    'GET /sections',
    (_) => ok([
      {'id': 'sb', 'name': 'B', 'class_id': 'k1'},
    ]),
  )
  ..on(
    'GET /classes',
    (_) => ok([
      {'id': 'k1', 'class_name': 'Morning'},
    ]),
  )
  ..on('POST /ielts/tests/t1/assignments', (_) => ok({'id': 'a2'}))
  ..on('PATCH /ielts/assignments/a1', (_) => ok({'id': 'a1'}))
  ..on('DELETE /ielts/assignments/a1', (_) => ok(null))
  ..on('POST /ielts/assignments/a1/speaking', (_) => ok({'attempt_id': 'sp1'}));

Future<ProviderContainer> _open(
  WidgetTester tester,
  FakeApi api, {
  String? lang,
}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: ieltsMember('TEACHER'),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go('/ielts/tests/t1/openings');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
  return app;
}

String _location(ProviderContainer app) => app
    .read(routerProvider)
    .routerDelegate
    .currentConfiguration
    .last
    .matchedLocation;

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  test('a day and a time in Dhaka make the right instant', () {
    expect(fromWallClock('2026-11-25', 9, 0), DateTime.utc(2026, 11, 25, 3));
  });

  testWidgets('openings: window, hand-ins per module; results', (tester) async {
    await _open(tester, _api());
    expect(find.text(_en.ieltsOpeningsTitle('Full mock 1')), findsOneWidget);
    expect(find.text('Evening A'), findsOneWidget);
    expect(
      find.textContaining('Listening 10/12 · Reading 9/12'),
      findsOneWidget,
    );
    await _tap(tester, find.byKey(const Key('opening-results-a1')));
    expect(find.text('Tania Akter'), findsOneWidget);
    expect(find.text('Listening: 7.0 (31/40)'), findsOneWidget);
    expect(
      find.text('Reading: ${_en.ieltsOpeningsInProgress}'),
      findsOneWidget,
    );
    expect(
      find.text('Writing: ${_en.ieltsOpeningsWaitingForMarks}'),
      findsOneWidget,
    );
    expect(
      find.text('Speaking: ${_en.ieltsOpeningsNotStarted}'),
      findsOneWidget,
    );
  });

  testWidgets('a link in the results closes the sheet, then opens the page', (
    tester,
  ) async {
    final app = await _open(tester, _api());
    await _tap(tester, find.byKey(const Key('opening-results-a1')));
    await _tap(tester, find.byKey(const Key('report-s1')));
    expect(find.byKey(const Key('result-s1')), findsNothing);
    expect(_location(app), '/ielts/report/a1/s1');
  });

  testWidgets('Examine starts the session, closes the sheet, opens it', (
    tester,
  ) async {
    final api = _api();
    final app = await _open(tester, api);
    await _tap(tester, find.byKey(const Key('opening-results-a1')));
    await _tap(tester, find.byKey(const Key('examine-s1')));
    expect(api.to('POST /ielts/assignments/a1/speaking').single.body, {
      'student_id': 's1',
    });
    expect(find.byKey(const Key('result-s1')), findsNothing);
    expect(_location(app), '/ielts/speaking/sp1');
  });

  testWidgets('open for another batch: batch and window', (tester) async {
    final api = _api();
    await _open(tester, api);
    await _tap(tester, find.byKey(const Key('opening-new')));
    final save = find.byKey(const Key('opening-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await _tap(tester, find.byKey(const Key('opening-batch')));
    await tester.tap(find.text('Morning B').last);
    await tester.pumpAndSettle();
    // The dates are still missing.
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
  });

  testWidgets('change the window, keeping the times', (tester) async {
    final api = _api();
    await _open(tester, api);
    await _tap(tester, find.byKey(const Key('opening-change-a1')));
    await _tap(tester, find.byKey(const Key('opening-save')));
    expect(api.to('PATCH /ielts/assignments/a1').single.body, {
      'opens_at': '2026-11-25T03:00:00.000Z',
      'closes_at': '2026-11-25T11:00:00.000Z',
    });
  });

  testWidgets('remove after asking', (tester) async {
    final api = _api();
    await _open(tester, api);
    await _tap(tester, find.byKey(const Key('opening-remove-a1')));
    expect(
      find.text(_en.ieltsOpeningsRemoveDescription('Evening A')),
      findsOneWidget,
    );
    await _tap(tester, find.byKey(const Key('opening-remove-confirm')));
    expect(api.to('DELETE /ielts/assignments/a1'), hasLength(1));
  });

  testWidgets('a draft must be published first', (tester) async {
    await _open(tester, _api(status: 'DRAFT'));
    expect(find.text(_en.ieltsOpeningsPublishFirst), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('opening-new')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.ieltsOpeningsOpen), findsWidgets);
    expect(tester.takeException(), isNull);
    await _tap(tester, find.byKey(const Key('opening-change-a1')));
    expect(tester.takeException(), isNull);
  });
}

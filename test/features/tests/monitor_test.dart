import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/tests/data/monitor.dart';
import 'package:instructor_app/features/tests/screens/monitor_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Session _teacher() =>
    Session.fromPayload({...sessionPayload(), 'role': 'TEACHER'});

/// The live connection, driven by the test.
class _Live implements MonitorLive {
  final events$ = StreamController<MonitorEvent>.broadcast();
  final connected$ = StreamController<bool>.broadcast();
  final joined = <String>[];

  @override
  Stream<MonitorEvent> get events => events$.stream;

  @override
  Stream<bool> get connected => connected$.stream;

  @override
  void join(String examId) => joined.add(examId);

  @override
  void dispose() {}
}

Map<String, Object?> _s(
  String id,
  String name, {
  String status = 'WRITING',
  int flags = 0,
  String? flag,
}) => {
  'studentId': id,
  'studentName': name,
  'liveStatus': status,
  'flagCount': flags,
  'totalFlagPoints': flags,
  'latestFlag': flag == null
      ? null
      : {'id': 'f', 'type': flag, 'message': '', 'points': 1, 'timestamp': ''},
  'deadline': DateTime.now()
      .toUtc()
      .add(const Duration(minutes: 10))
      .toIso8601String(),
};

FakeApi _api({FakeHandler? sessions}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on('GET /exams', (_) => ok(<Object>[]))
  ..on('GET /exams/e1', (_) => ok({'id': 'e1', 'test_name': 'Algebra quiz'}))
  ..on(
    'GET /exams/e1/proctoring/sessions',
    sessions ??
        (_) => ok({
          'sessions': [
            _s('s1', 'Karim Hasan', flags: 6, flag: 'tab-switch'),
            _s('s2', 'Nadia Islam', status: 'SUBMITTED'),
          ],
        }),
  )
  ..on(
    'GET /exams/e1/proctoring/students/s1/timeline',
    (_) => ok([
      {
        'id': 'ev1',
        'type': 'tab-switch',
        'occurred_at': '2026-11-18T04:00:00.000Z',
        'source': 'CLIENT',
      },
      {
        'id': 'ev2',
        'type': 'teacher-warning',
        'occurred_at': '2026-11-18T04:01:00.000Z',
        'message': 'Eyes on your screen',
        'source': 'SERVER',
      },
    ]),
  )
  ..on(
    'POST /exams/e1/proctoring/students/s1/warn',
    (_) => ok(<String, Object>{}),
  )
  ..on(
    'POST /exams/e1/proctoring/students/s1/end',
    (_) => ok(<String, Object>{}),
  );

Future<_Live> _open(WidgetTester tester, FakeApi api, {String? lang}) async {
  final live = _Live();
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _teacher(),
    prefs: {'language': ?lang},
    overrides: [monitorLiveProvider.overrideWithValue(live)],
  );
  app.read(routerProvider).go('/tests/e1/monitor');
  await tester.pumpAndSettle();
  return live;
}

/// An event from the live connection arrives, then the screen draws.
Future<void> _arrive(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 10));

/// The monitor ticks every second: leave it before the test ends.
Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 31));
}

void main() {
  test('risk by flags, as the web colours tiles', () {
    expect(riskOf(0), 'none');
    expect(riskOf(1), 'some');
    expect(riskOf(5), 'high');
  });

  testWidgets('tiles: status, flags, latest flag; joins the monitor room', (
    tester,
  ) async {
    final live = await _open(tester, _api());
    expect(find.byType(MonitorScreen), findsOneWidget);
    expect(live.joined, ['e1']);
    expect(find.byKey(const Key('tile-s1')), findsOneWidget);
    expect(find.text(_en.monitorStatusSUBMITTED), findsOneWidget);
    expect(find.text(_en.monitorFlags(6)), findsOneWidget);
    expect(find.text(_en.monitorEventsTabSwitch), findsOneWidget);
    expect(find.text(_en.monitorSummary(1, 0, 1)), findsOneWidget);
    expect(find.textContaining(_en.monitorConnecting), findsOneWidget);
    live.connected$.add(true);
    await _arrive(tester);
    expect(
      tester.widget<Text>(find.byKey(const Key('monitor-connection'))).data,
      endsWith(_en.monitorLive),
    );
    await _end(tester);
  });

  testWidgets('live: a lost student and a new flag change their tile', (
    tester,
  ) async {
    final live = await _open(tester, _api());
    live.events$.add(SessionChanged('s1', status: 'LOST'));
    await _arrive(tester);
    expect(find.text(_en.monitorStatusLOST), findsOneWidget);
    live.events$.add(
      SessionChanged('s1', status: 'WRITING', flagCount: 7, flag: 'no-face'),
    );
    await _arrive(tester);
    expect(find.text(_en.monitorFlags(7)), findsOneWidget);
    expect(find.text(_en.monitorEventsNoFace), findsOneWidget);
    live.events$.add(MonitorAlert('Karim Hasan', 7));
    await _arrive(tester);
    expect(
      find.textContaining(_en.monitorAlertTitle('Karim Hasan')),
      findsOneWidget,
    );
    await _end(tester);
  });

  testWidgets('a student: timeline; warn; end with a reason', (tester) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('tile-s1')));
    await tester.pumpAndSettle();
    expect(find.text(_en.monitorEventsTabSwitch), findsOneWidget);
    expect(
      find.text('${_en.monitorEventsTeacherWarning}: Eyes on your screen'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('warn-text')),
      ' Look at your own paper ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('warn-send')));
    await tester.pumpAndSettle();
    expect(api.to('POST /exams/e1/proctoring/students/s1/warn').single.body, {
      'message': 'Look at your own paper',
    });
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('end-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('end-open')));
    await tester.pumpAndSettle();
    // A reason is needed.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('end-confirm')))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('end-reason')), 'Phone use');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('end-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('end-confirm')));
    await tester.pumpAndSettle();
    expect(api.to('POST /exams/e1/proctoring/students/s1/end').single.body, {
      'reason': 'Phone use',
    });
    // Back on the monitor, the tile says Ended.
    expect(find.byType(MonitorScreen), findsOneWidget);
    expect(find.text(_en.monitorStatusENDED), findsOneWidget);
    await _end(tester);
  });

  testWidgets('nobody yet; not allowed', (tester) async {
    await _open(tester, _api(sessions: (_) => ok({'sessions': <Object>[]})));
    expect(find.text(_en.monitorEmpty), findsOneWidget);
    await _end(tester);
  });

  testWidgets('not the test\'s teacher: not allowed', (tester) async {
    await _open(tester, _api(sessions: (_) => apiError(403)));
    expect(find.text(_en.monitorNotAllowed), findsOneWidget);
    await _end(tester);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.monitorTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _end(tester);
  });
}

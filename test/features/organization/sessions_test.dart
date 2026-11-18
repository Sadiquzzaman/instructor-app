import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/widgets/date_field.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Session _member(String role) {
  final p = sessionPayload();
  return Session.fromPayload({
    ...p,
    'role': 'TEACHER',
    'organization': <String, dynamic>{
      ...(p['organization'] as Map<String, dynamic>),
      'role': role,
    },
  });
}

FakeApi _api() => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
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
      {
        'id': 'se0',
        'name': '2025',
        'start_date': '2025-01-01',
        'end_date': '2025-12-31',
        'status': 'CLOSED',
        'is_default': false,
      },
    ]),
  )
  ..on('POST /sessions', (_) => ok({'id': 'se2'}))
  ..on('POST /sessions/se1/close', (_) => ok(null))
  ..on('POST /sessions/se0/reopen', (_) => ok(null))
  ..on(
    'GET /sessions/se1/terms',
    (_) => ok([
      {
        'id': 't1',
        'name': 'Half-yearly',
        'start_date': '2026-01-01',
        'end_date': '2026-06-30',
      },
    ]),
  )
  ..on('GET /sessions/se0/terms', (_) => ok(<Object>[]))
  ..on('POST /sessions/se1/terms', (_) => ok({'id': 't2'}))
  ..on('DELETE /terms/t1', (_) => ok(null));

Future<void> _open(
  WidgetTester tester,
  FakeApi api, {
  String role = 'OWNER',
  String? lang,
}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _member(role),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go('/sessions');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

Future<void> _pickDay(WidgetTester tester, Finder field, String day) async {
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(day).last);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  test('a picked day is written as the API wants it', () {
    expect(DateField.format(DateTime(2026, 3, 7)), '2026-03-07');
  });

  testWidgets('sessions: default, active and closed', (tester) async {
    await _open(tester, _api());
    expect(find.text('2026'), findsOneWidget);
    expect(find.text(_en.academicsSessionsDefault), findsOneWidget);
    expect(find.text(_en.academicsSessionsStatusClosed), findsOneWidget);
    expect(find.byKey(const Key('close-se1')), findsOneWidget);
    expect(find.byKey(const Key('default-se1')), findsNothing);
    expect(find.byKey(const Key('reopen-se0')), findsOneWidget);
  });

  testWidgets('add a session: name and both dates', (tester) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('session-add')));
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('session-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('session-name')), ' 2027 ');
    await _pickDay(tester, find.byKey(const Key('session-start')), '15');
    await _pickDay(tester, find.byKey(const Key('session-end')), '28');
    await tester.tap(find.byKey(const Key('session-default')));
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    final body = api.to('POST /sessions').single.body! as Map;
    expect(body['name'], '2027');
    expect(body['is_default'], isTrue);
    expect((body['start_date'] as String).endsWith('-15'), isTrue);
    expect((body['end_date'] as String).endsWith('-28'), isTrue);
  });

  testWidgets('close asks first; reopen', (tester) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('close-se1')));
    await tester.pumpAndSettle();
    expect(find.text(_en.academicsSessionsCloseTitle('2026')), findsOneWidget);
    await tester.tap(find.byKey(const Key('session-close-confirm')));
    await tester.pumpAndSettle();
    expect(api.to('POST /sessions/se1/close'), hasLength(1));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reopen-se0')));
    await tester.pumpAndSettle();
    expect(api.to('POST /sessions/se0/reopen'), hasLength(1));
  });

  testWidgets('admins do not reopen; teachers have no access', (tester) async {
    await _open(tester, _api(), role: 'ADMIN');
    expect(find.byKey(const Key('close-se1')), findsOneWidget);
    expect(find.byKey(const Key('reopen-se0')), findsNothing);
  });

  testWidgets('teachers in an organisation: no access', (tester) async {
    await _open(tester, _api(), role: 'TEACHER');
    expect(find.text(_en.academicsSessionsNoAccess), findsOneWidget);
  });

  testWidgets('terms: add one, delete one (asked first)', (tester) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('terms-se1')));
    await tester.pumpAndSettle();
    expect(find.text('Half-yearly'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('term-name')), 'Annual');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('term-save')));
    await tester.tap(find.byKey(const Key('term-save')));
    await tester.pumpAndSettle();
    expect(api.to('POST /sessions/se1/terms').single.body, {
      'name': 'Annual',
      'sort_order': 1,
    });
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('term-delete-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('term-delete-confirm')));
    await tester.pumpAndSettle();
    expect(api.to('DELETE /terms/t1'), hasLength(1));
  });

  testWidgets('a closed session\'s terms are read-only', (tester) async {
    await _open(tester, _api());
    await tester.tap(find.byKey(const Key('terms-se0')));
    await tester.pumpAndSettle();
    expect(find.text(_en.academicsTermsClosedNote), findsOneWidget);
    expect(find.byKey(const Key('term-name')), findsNothing);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.academicsSessionsTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

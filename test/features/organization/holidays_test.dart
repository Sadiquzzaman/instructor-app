import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();
final _year = int.parse(OrgTime.today().substring(0, 4));

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

FakeApi _api({FakeHandler? save}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /attendance/settings',
    (_) => ok({
      'late_grace_minutes': 10,
      'weekly_off_days': [5, 6],
      'guardian_sms': <String, bool>{},
      'repeat_absence_days': 3,
    }),
  )
  ..on(
    'GET /holidays',
    (_) => ok([
      {
        'id': 'h0',
        'date_from': '${_year - 1}-12-25',
        'date_to': '${_year - 1}-12-25',
        'name': 'Victory Day',
        'days': 1,
      },
      {
        'id': 'h1',
        'date_from': '${_year + 1}-02-21',
        'date_to': '${_year + 1}-02-23',
        'name': 'Winter break',
        'days': 3,
      },
    ]),
  )
  ..on('POST /holidays', save ?? (_) => ok({'id': 'h2'}))
  ..on('DELETE /holidays/h1', (_) => ok(null));

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
  app.read(routerProvider).go('/holidays');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the year, the weekly off days, past and upcoming', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    expect(api.to('GET /holidays').single.query, {
      'from': '$_year-01-01',
      'to': '$_year-12-31',
    });
    // The school week starts on Saturday.
    expect(find.text(_en.holidaysOffDays('Saturday, Friday')), findsOneWidget);
    expect(find.byKey(const Key('holiday-off-days')), findsOneWidget);
    expect(find.text(_en.holidaysSummary(2, 4)), findsOneWidget);
    expect(find.text(_en.holidaysWhenPast), findsOneWidget);
    expect(find.text(_en.holidaysWhenUpcoming), findsOneWidget);
    // Past days are locked; later ones can change.
    expect(find.byKey(const Key('holiday-edit-h0')), findsNothing);
    expect(find.text(_en.holidaysLocked), findsOneWidget);
    expect(find.byKey(const Key('holiday-edit-h1')), findsOneWidget);
  });

  testWidgets('another year asks for that year', (tester) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('holiday-year')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${_year + 1}').last);
    await tester.pumpAndSettle();
    expect(api.to('GET /holidays').last.query['from'], '${_year + 1}-01-01');
  });

  testWidgets('add one day: the last day is the first unless chosen', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('holiday-add')));
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('holiday-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(find.byKey(const Key('holiday-from')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('holiday-note')), ' Exams ');
    await tester.tap(save);
    await tester.pumpAndSettle();
    final body = api.to('POST /holidays').single.body! as Map;
    expect(body['date_from'], OrgTime.today());
    expect(body['date_to'], body['date_from']);
    expect(body['name'], 'Exams');
  });

  testWidgets('a refusal in the web\'s words', (tester) async {
    await _open(
      tester,
      _api(save: (_) => apiError(400, code: 'HOLIDAY_RANGE_TOO_LONG')),
    );
    await tester.tap(find.byKey(const Key('holiday-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('holiday-from')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('holiday-save')));
    await tester.pumpAndSettle();
    expect(find.text(_en.holidaysErrorsHOLIDAYRANGETOOLONG), findsOneWidget);
  });

  testWidgets('remove asks first', (tester) async {
    final api = _api();
    await _open(tester, api);
    await tester.ensureVisible(find.byKey(const Key('holiday-remove-h1')));
    await tester.tap(find.byKey(const Key('holiday-remove-h1')));
    await tester.pumpAndSettle();
    expect(find.text(_en.holidaysRemoveTitle), findsOneWidget);
    await tester.tap(find.byKey(const Key('holiday-remove-confirm')));
    await tester.pumpAndSettle();
    expect(api.to('DELETE /holidays/h1'), hasLength(1));
  });

  testWidgets('teachers read only', (tester) async {
    await _open(tester, _api(), role: 'TEACHER');
    expect(find.byKey(const Key('holiday-add')), findsNothing);
    expect(find.byKey(const Key('holiday-edit-h1')), findsNothing);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.holidaysTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

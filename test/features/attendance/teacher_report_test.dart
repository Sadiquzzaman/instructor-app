import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/attendance/screens/teacher_report.dart';
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
    'GET /attendance/register/sections',
    (_) => ok([
      {
        'id': 'sec1',
        'name': 'A',
        'class_name': 'Class 6',
        'mode': 'SELF_CHECKIN',
      },
    ]),
  )
  ..on(
    'GET /attendance/reports/daily',
    (_) => ok({'date': '2026-11-18', 'sections': <Object>[]}),
  )
  ..on(
    'GET /attendance/reports/teachers',
    (r) => ok({
      'from': r.query['from'] ?? '2026-11-18',
      'to': r.query['to'] ?? '2026-11-18',
      'today': '2026-11-18',
      'teachers': [
        {
          'teacher': {'id': 't1', 'full_name': 'Rina Akter'},
          'counts': {'present': 3, 'late': 1, 'absent': 0, 'leave': 0},
          'attendance_pct': 75,
          'late_minutes': 7,
          'classes': [
            {
              'date': '2026-11-18',
              'start_time': '10:00',
              'end_time': '10:45',
              'section': {'class_name': 'Class 6', 'name': 'A'},
              'status': 'LATE',
              'late_minutes': 7,
            },
          ],
        },
      ],
    }),
  );

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
  app.read(routerProvider).go('/attendance-reports');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

void main() {
  test('a month runs from the 1st to its last day', () {
    expect(monthRange('2026-02'), (from: '2026-02-01', to: '2026-02-28'));
    expect(monthRange('2028-02'), (from: '2028-02-01', to: '2028-02-29'));
    expect(monthRange('2026-12'), (from: '2026-12-01', to: '2026-12-31'));
  });

  testWidgets('owners: each teacher with counts and the class not on time', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('tab-teachers')));
    await tester.pumpAndSettle();
    expect(find.text('Rina Akter'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(find.textContaining(_en.reportsMinutesLate(7)), findsOneWidget);
    await tester.tap(find.byKey(const Key('tr-month')));
    await tester.pumpAndSettle();
    expect(api.to('GET /attendance/reports/teachers').last.query, {
      'from': '2026-11-01',
      'to': '2026-11-30',
    });
  });

  testWidgets('teachers do not get the teachers tab', (tester) async {
    await _open(tester, _api(), role: 'TEACHER');
    expect(find.byKey(const Key('tab-teachers')), findsNothing);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    await tester.tap(find.byKey(const Key('tab-teachers')));
    await tester.pumpAndSettle();
    expect(find.text(bn.reportsTeachersTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

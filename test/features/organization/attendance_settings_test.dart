import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/organization/screens/attendance_settings_screen.dart';
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

Map<String, Object?> _settings() => {
  'late_grace_minutes': 10,
  'weekly_off_days': [5],
  'guardian_sms': {'late': false, 'absent': true, 'leave': false},
  'repeat_absence_days': 3,
};

FakeApi _api() => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on('GET /attendance/settings', (_) => ok(_settings()))
  ..on(
    'PATCH /attendance/settings',
    (r) => ok({..._settings(), ...(r.body! as Map).cast<String, Object?>()}),
  )
  ..on(
    'GET /attendance/branches',
    (_) => ok([
      {
        'id': 'b1',
        'name': null,
        'geo_lat': 23.8,
        'geo_lng': 90.4,
        'checkin_radius_m': 150,
        'is_default': true,
        'section_count': 4,
      },
      {
        'id': 'b2',
        'name': 'Uttara',
        'geo_lat': null,
        'geo_lng': null,
        'checkin_radius_m': 100,
        'is_default': false,
        'section_count': 0,
      },
    ]),
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
  app.read(routerProvider).go('/attendance-settings');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

Finder _scrollable() => find
    .descendant(
      of: find.byType(AttendanceSettingsScreen),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _show(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: _scrollable());
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the branches with their radius or no pin', (tester) async {
    await _open(tester, _api());
    expect(find.text(_en.attendanceSettingsBranchesSummary(2)), findsOneWidget);
    expect(find.text(_en.branchesMainBranch), findsOneWidget);
    expect(find.text(_en.branchesRadiusShort('150')), findsOneWidget);
    expect(find.text(_en.branchesNoPin), findsOneWidget);
  });

  testWidgets('change the grace, a day off and an SMS; save sends all', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    final save = find.byKey(const Key('settings-save'));
    await _show(tester, save);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await _show(tester, find.byKey(const Key('settings-grace')));
    await tester.enterText(find.byKey(const Key('settings-grace')), '15');
    await _show(tester, find.byKey(const Key('off-6')));
    await tester.tap(find.byKey(const Key('off-6')));
    await _show(tester, find.byKey(const Key('sms-late')));
    await tester.tap(find.byKey(const Key('sms-late')));
    await tester.pumpAndSettle();
    await _show(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(api.to('PATCH /attendance/settings').single.body, {
      'late_grace_minutes': 15,
      'weekly_off_days': [5, 6],
      'guardian_sms': {'late': true, 'absent': true, 'leave': false},
      'repeat_absence_days': 3,
    });
    expect(find.text(_en.attendanceSettingsSaved), findsOneWidget);
  });

  testWidgets('limits: grace 0–60, repeat 2–30, a working day', (tester) async {
    await _open(tester, _api());
    await _show(tester, find.byKey(const Key('settings-grace')));
    await tester.enterText(find.byKey(const Key('settings-grace')), '61');
    await tester.pump();
    expect(find.text(_en.attendanceSettingsGraceError), findsOneWidget);
    await tester.enterText(find.byKey(const Key('settings-grace')), '10');
    await _show(tester, find.byKey(const Key('settings-repeat')));
    await tester.enterText(find.byKey(const Key('settings-repeat')), '1');
    await tester.pump();
    expect(find.text(_en.attendanceSettingsRepeatDaysError), findsOneWidget);
    final save = find.byKey(const Key('settings-save'));
    await _show(tester, save);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
  });

  testWidgets('undo puts the saved values back', (tester) async {
    await _open(tester, _api());
    await _show(tester, find.byKey(const Key('settings-grace')));
    await tester.enterText(find.byKey(const Key('settings-grace')), '20');
    await _show(tester, find.byKey(const Key('settings-undo')));
    await tester.tap(find.byKey(const Key('settings-undo')));
    await tester.pumpAndSettle();
    await _show(tester, find.byKey(const Key('settings-grace')));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('settings-grace')))
          .controller!
          .text,
      '10',
    );
  });

  testWidgets('teachers read only', (tester) async {
    await _open(tester, _api(), role: 'TEACHER');
    expect(find.byKey(const Key('settings-read-only')), findsOneWidget);
    expect(find.byKey(const Key('settings-save')), findsNothing);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.attendanceSettingsTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

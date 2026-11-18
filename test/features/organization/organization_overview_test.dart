import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/organization/screens/organization_overview_screen.dart';
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

Map<String, Object?> _settings({bool branches = false, String sms = 'bn'}) => {
  'class_teacher_enabled': true,
  'branches_enabled': branches,
  'guardians_enabled': false,
  'default_locale': 'bn',
  'sms_locale': sms,
};

FakeApi _api({String status = 'approved', bool setupDone = false}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /organizations/org-1',
    (_) => ok({
      'id': 'org-1',
      'name': 'Demo School',
      'organization_number': 1042,
      'status': status,
      'teachers_count': 12,
      'students_count': 340,
      'classes_count': 10,
      'exams_count': 25,
    }),
  )
  ..on('GET /organizations/org-1/settings', (_) => ok(_settings()))
  ..on(
    'PATCH /organizations/org-1/settings',
    (r) => ok({..._settings(), ...(r.body! as Map).cast<String, Object?>()}),
  )
  ..on(
    'GET /setup',
    (_) => ok({
      'setup_completed_at': setupDone ? '2026-11-01T00:00:00Z' : null,
      'classes': <Object>[],
    }),
  );

Future<List<Uri>> _open(
  WidgetTester tester,
  FakeApi api,
  String role, {
  String? lang,
}) async {
  final links = <Uri>[];
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _member(role),
    prefs: {'language': ?lang},
    openedLinks: links,
  );
  app.read(routerProvider).go('/organization');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
  return links;
}

Future<void> _show(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    200,
    scrollable: find
        .descendant(
          of: find.byType(OrganizationOverviewScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('owners: counts, details, setup banner and settings', (
    tester,
  ) async {
    final links = await _open(tester, _api(), 'OWNER');
    expect(find.text(_en.organizationOverviewTitle), findsOneWidget);
    expect(find.text('340'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('1042'), findsOneWidget);
    expect(find.text(_en.organizationStatusesApproved), findsOneWidget);
    expect(find.text(_en.organizationRolesOWNER), findsOneWidget);

    expect(find.byKey(const Key('setup-banner')), findsOneWidget);
    await tester.tap(find.byKey(const Key('setup-open')));
    await tester.pumpAndSettle();
    expect(links.single.path, '/organization/setup');

    await _show(tester, 'org-settings');
    expect(find.text(_en.academicsSettingsTitle), findsOneWidget);
  });

  testWidgets('a setting saves at once', (tester) async {
    final api = _api();
    await _open(tester, api, 'ADMIN');
    await _show(tester, 'setting-branches');
    await tester.tap(find.byKey(const Key('setting-branches')));
    await tester.pumpAndSettle();
    expect(api.to('PATCH /organizations/org-1/settings').single.body, {
      'branches_enabled': true,
    });
    expect(find.text(_en.academicsSettingsSaved), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('setting-branches')))
          .value,
      isTrue,
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _show(tester, 'setting-sms-language');
    await tester.tap(find.byKey(const Key('setting-sms-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.academicsSettingsLanguagesEn).last);
    await tester.pumpAndSettle();
    expect(api.to('PATCH /organizations/org-1/settings').last.body, {
      'sms_locale': 'en',
    });
  });

  testWidgets('setup finished: no banner', (tester) async {
    await _open(tester, _api(setupDone: true), 'OWNER');
    expect(find.byKey(const Key('setup-banner')), findsNothing);
  });

  testWidgets('assistants see the numbers only', (tester) async {
    final api = _api();
    await _open(tester, api, 'ASSISTANT');
    expect(find.text('340'), findsOneWidget);
    expect(find.byKey(const Key('setup-banner')), findsNothing);
    expect(find.byKey(const Key('org-settings')), findsNothing);
    expect(api.to('GET /organizations/org-1/settings'), isEmpty);
  });

  testWidgets('teachers: not for their role', (tester) async {
    final api = _api();
    await _open(tester, api, 'TEACHER');
    expect(find.text(_en.organizationGateNoAccessTitle), findsOneWidget);
    expect(api.to('GET /organizations/org-1'), isEmpty);
  });

  testWidgets('waiting for approval says so', (tester) async {
    await _open(tester, _api(status: 'pending'), 'OWNER');
    expect(find.text(_en.organizationGatePendingTitle), findsOneWidget);
    expect(find.text(_en.organizationStatusesPending), findsOneWidget);
  });

  testWidgets('a failure offers a retry', (tester) async {
    final api = _api()..on('GET /organizations/org-1', (_) => apiError(500));
    await _open(tester, api, 'OWNER');
    expect(find.text(_en.organizationOverviewLoadFailed), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), 'OWNER', lang: 'bn');
    expect(find.text(bn.organizationOverviewTitle), findsOneWidget);
    expect(find.text('৩৪০'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

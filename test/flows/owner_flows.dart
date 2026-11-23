import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/organization/screens/organization_overview_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

/// An owner's main flows (Stage 3 plan, PR 13), end to end through the
/// app's own screens, against the in-process fake API: see the
/// organisation, add a teacher, set who teaches what, change a setting,
/// close a session. Run by `flutter test` (test/flows) and on a device by
/// `flutter test integration_test`.
void ownerFlows() {
  testWidgets('the organisation, then add a teacher found by phone', (
    tester,
  ) async {
    final api = _school();
    final c = await _signedIn(tester, api);
    await _go(tester, c, '/organization');
    expect(find.byType(OrganizationOverviewScreen), findsOneWidget);
    expect(find.text('340'), findsOneWidget);

    await _go(tester, c, '/organization/teachers');
    await tester.tap(find.byKey(const Key('people-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('lookup-query')),
      '01100000009',
    );
    await tester.tap(find.byKey(const Key('lookup-find')));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('lookup-add')));
    expect(api.to('POST /organizations/org-1/members').single.body, {
      'query': '01100000009',
      'role': 'TEACHER',
    });
  });

  testWidgets('who teaches what: fill an empty subject class', (tester) async {
    final api = _school();
    final c = await _signedIn(tester, api);
    await _go(tester, c, '/organization/assignments');
    final quick = find.byKey(const Key('quick-ob'));
    await tester.scrollUntilVisible(
      quick,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(quick);
    await tester.pumpAndSettle();
    await tester.tap(quick);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jamal Uddin').last);
    await tester.pumpAndSettle();
    expect(api.to('PUT /offerings/ob/teachers').single.body, {
      'teacher_ids': ['t2'],
    });
  });

  testWidgets('change a setting: homework late penalty', (tester) async {
    final api = _school();
    final c = await _signedIn(tester, api);
    await _go(tester, c, '/homework-settings');
    await tester.tap(find.byKey(const Key('hw-penalty')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.homeworkSettingsPenaltiesFIXED).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('hw-percent')), '20');
    await _tap(tester, find.byKey(const Key('hw-save')));
    final body = api.to('PATCH /homework/settings').single.body! as Map;
    expect(body['late_penalty'], {'type': 'FIXED', 'percent': 20});
  });

  testWidgets('close a session after asking', (tester) async {
    final api = _school();
    final c = await _signedIn(tester, api);
    await _go(tester, c, '/sessions');
    await tester.tap(find.byKey(const Key('close-se1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('session-close-confirm')));
    await tester.pumpAndSettle();
    expect(api.to('POST /sessions/se1/close'), hasLength(1));
    expect(find.text(_en.academicsSessionsClosed), findsOneWidget);
  });
}

final _en = AppLocalizationsEn();

Future<ProviderContainer> _signedIn(WidgetTester tester, FakeApi api) {
  final p = sessionPayload();
  return pumpInstructorApp(
    tester,
    api: api,
    session: Session.fromPayload({
      ...p,
      'role': 'TEACHER',
      'full_name': 'Owner Person',
      'organization': <String, dynamic>{
        ...(p['organization'] as Map<String, dynamic>),
        'role': 'OWNER',
      },
    }),
    prefs: {'language': 'en'},
  );
}

Future<void> _go(WidgetTester tester, ProviderContainer c, String route) async {
  c.read(routerProvider).go(route);
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Map<String, Object?> _hw() => {
  'late_allowed': true,
  'late_penalty': {'type': 'NONE', 'percent': 0},
  'resubmissions': 1,
  'max_files': 5,
};

/// One school as its owner.
FakeApi _school() => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  // Organisation.
  ..on(
    'GET /organizations/org-1',
    (_) => ok({
      'name': 'Demo School',
      'organization_number': 1042,
      'status': 'approved',
      'teachers_count': 12,
      'students_count': 340,
      'classes_count': 10,
      'exams_count': 25,
    }),
  )
  ..on(
    'GET /organizations/org-1/settings',
    (_) => ok({
      'class_teacher_enabled': true,
      'branches_enabled': false,
      'guardians_enabled': false,
      'default_locale': 'bn',
      'sms_locale': 'bn',
    }),
  )
  ..on(
    'GET /setup',
    (_) => ok({
      'setup_completed_at': '2026-01-01T00:00:00Z',
      'classes': <Object>[],
    }),
  )
  // People.
  ..on('GET /organizations/org-1/members', (_) => ok(<Object>[]))
  ..on(
    'GET /organizations/org-1/members/lookup',
    (_) => ok({
      'found': true,
      'user': {
        'id': 'u9',
        'full_name': 'Jamal Uddin',
        'phone': '01100000009',
        'is_otp_verified': true,
      },
      'membership': null,
    }),
  )
  ..on(
    'POST /organizations/org-1/members',
    (_) => ok({'status': 'added', 'member': <String, Object>{}}),
  )
  // Who teaches what.
  ..on(
    'GET /classes',
    (_) => ok([
      {'id': 'c6', 'class_name': 'Class 6', 'classSubjects': <Object>[]},
    ]),
  )
  ..on('GET /organizations/org-1/subjects', (_) => ok(<Object>[]))
  ..on(
    'GET /organizations/org-1/assignable-teachers',
    (_) => ok([
      {
        'user': {'id': 't2', 'full_name': 'Jamal Uddin'},
      },
    ]),
  )
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
    ]),
  )
  ..on(
    'GET /sections',
    (_) => ok([
      {'id': 'sb', 'name': 'B', 'class_id': 'c6'},
    ]),
  )
  ..on(
    'GET /offerings',
    (_) => ok([
      {
        'id': 'ob',
        'section_id': 'sb',
        'subject': {'id': 'm', 'name': 'Mathematics', 'code': null},
        'teachers': <Object>[],
      },
    ]),
  )
  ..on('PUT /offerings/ob/teachers', (_) => ok(null))
  // Settings and sessions.
  ..on('GET /homework/settings', (_) => ok(_hw()))
  ..on(
    'PATCH /homework/settings',
    (r) => ok({..._hw(), ...(r.body! as Map).cast<String, Object?>()}),
  )
  ..on('POST /sessions/se1/close', (_) => ok(null));

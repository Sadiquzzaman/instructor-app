import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/organization/screens/organization_overview_screen.dart';
import 'package:instructor_app/features/organization/screens/setup_wizard_screen.dart';
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

Map<String, Object?> _setup({bool sections = false}) => {
  'setup_completed_at': null,
  'session': {'id': 'se1', 'name': '2026'},
  'classes': [
    {
      'id': 'c6',
      'name': 'Class 6',
      'subject_count': 1,
      'section_count': sections ? 1 : 0,
      'student_count': 0,
      'subjects_without_teacher': <Object>[],
    },
  ],
  'checkin_pin_missing': true,
};

FakeApi _api({bool sections = false}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok({'preset': 'CLASS_SECTION'}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
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
  ..on('PATCH /workspace/level-labels', (r) => ok(r.body))
  ..on('GET /setup', (_) => ok(_setup(sections: sections)))
  ..on('POST /setup/complete', (_) => ok(null))
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
  ..on('POST /classes', (_) => ok({'id': 'c7'}))
  ..on(
    'GET /classes/c6/subjects',
    (_) => ok([
      {
        'id': 'cs1',
        'subject_id': 'm',
        'subject': {'id': 'm', 'name': 'Mathematics'},
      },
    ]),
  )
  ..on(
    'GET /organizations/org-1/subjects',
    (_) => ok([
      {'id': 'm', 'name': 'Mathematics', 'code': 'M', 'classes': <Object>[]},
      {'id': 'e', 'name': 'English', 'code': 'E', 'classes': <Object>[]},
    ]),
  )
  ..on('POST /organizations/org-1/subjects', (_) => ok({'id': 'p'}))
  ..on('POST /classes/c6/subjects', (_) => ok(null))
  ..on('GET /classes/c6/sections', (_) => ok(<Object>[]))
  ..on('POST /classes/c6/sections', (_) => ok({'id': 'sa'}))
  ..on(
    'GET /organizations/org-1',
    (_) => ok({'name': 'Demo School', 'status': 'approved'}),
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
  app.read(routerProvider).go('/organization/setup');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    200,
    scrollable: find
        .descendant(
          of: find.byType(SetupWizardScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _step(WidgetTester tester, int i) async {
  await tester.tap(find.byKey(Key('setup-step-$i')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('basics: own words for the levels need all six names', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    await _tap(tester, find.byKey(const Key('preset-CUSTOM')));
    await tester.enterText(find.byKey(const Key('label-class-one')), '');
    await tester.pump();
    expect(find.text(_en.levelLabelsRequired(30)), findsOneWidget);
    await tester.enterText(find.byKey(const Key('label-class-one')), 'Grade');
    await tester.enterText(
      find.byKey(const Key('label-class-other')),
      'Grades',
    );
    await tester.pump();
    await _tap(tester, find.byKey(const Key('labels-save')));
    final body = api.to('PATCH /workspace/level-labels').single.body! as Map;
    expect(body['preset'], 'CUSTOM');
    expect(body['class'], {
      'en': {'one': 'Grade', 'other': 'Grades'},
      'bn': 'ক্লাস',
    });
  });

  testWidgets('classes: add a class; a new subject is made then added', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    await _step(tester, 2);
    await tester.enterText(
      find.byKey(const Key('setup-class-name')),
      ' Class 7 ',
    );
    await tester.pump();
    await _tap(tester, find.byKey(const Key('setup-class-add')));
    expect(api.to('POST /classes').single.body, {'class_name': 'Class 7'});

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('setup-subject-c6')));
    // Mathematics is already in the class; English and "new" are offered.
    expect(find.text('English').last, findsOneWidget);
    await tester.tap(find.text(_en.academicsSetupClassesNewSubjectOption).last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('setup-new-name-c6')),
      'Physics',
    );
    await tester.enterText(find.byKey(const Key('setup-new-code-c6')), 'PHY');
    await tester.pump();
    await _tap(tester, find.byKey(const Key('setup-subject-add-c6')));
    expect(api.to('POST /organizations/org-1/subjects').single.body, {
      'name': 'Physics',
      'code': 'PHY',
    });
    expect(api.to('POST /classes/c6/subjects').single.body, {
      'subject_id': 'p',
    });
  });

  testWidgets('sections: add one in the session', (tester) async {
    final api = _api();
    await _open(tester, api);
    await _step(tester, 3);
    await tester.enterText(find.byKey(const Key('setup-section-name-c6')), 'A');
    await tester.pump();
    await _tap(tester, find.byKey(const Key('setup-section-add-c6')));
    expect(api.to('POST /classes/c6/sections').single.body, {
      'name': 'A',
      'session_id': 'se1',
    });
  });

  testWidgets('summary: a class without sections blocks finishing', (
    tester,
  ) async {
    await _open(tester, _api());
    await _step(tester, 4);
    expect(find.byKey(const Key('summary-needs-section')), findsOneWidget);
    final finish = find.byKey(const Key('setup-finish'));
    await tester.ensureVisible(finish);
    expect(tester.widget<FilledButton>(finish).onPressed, isNull);
  });

  testWidgets('finish, then back on the overview', (tester) async {
    final api = _api(sections: true);
    await _open(tester, api);
    await _step(tester, 4);
    await _tap(tester, find.byKey(const Key('setup-finish')));
    expect(api.to('POST /setup/complete'), hasLength(1));
    expect(find.byType(OrganizationOverviewScreen), findsOneWidget);
  });

  testWidgets('teachers: not for their role', (tester) async {
    await _open(tester, _api(), role: 'TEACHER');
    expect(find.text(_en.organizationGateNoAccessTitle), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.academicsSetupTitle), findsOneWidget);
    for (final i in [1, 2, 3, 4]) {
      await _step(tester, i);
      expect(tester.takeException(), isNull);
    }
  });
}

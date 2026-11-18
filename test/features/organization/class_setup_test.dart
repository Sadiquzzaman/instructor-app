import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/organization/screens/class_setup_screen.dart';
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

Map<String, Object?> _section(
  String id,
  String name, {
  bool slots = true,
  bool canEdit = true,
}) => {
  'id': id,
  'name': name,
  'class': {'id': 'c6', 'name': 'Class 6'},
  'shift': 'MORNING',
  'slots': slots
      ? [
          for (final d in [1, 6, 2])
            {
              'day_of_week': d,
              'start_time': '10:00:00',
              'end_time': '10:45:00',
              'subject': {'name': 'Maths'},
              'teacher': {'full_name': 'Rina Akter'},
            },
        ]
      : <Object>[],
  'branch_id': 'b2',
  'class_type': 'IN_PERSON',
  'mode': 'SELF_CHECKIN',
  'grace_minutes': null,
  'can_edit': canEdit,
};

FakeApi _api({bool canManage = true}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on('GET /sessions', (_) => ok(<Object>[]))
  ..on(
    'GET /attendance/setup',
    (_) => ok({
      'session': {'id': 'se1', 'name': '2026'},
      'can_manage': canManage,
      'late_grace_minutes': 10,
      'sections': [_section('sa', 'A'), _section('sb', 'B', slots: false)],
    }),
  )
  ..on(
    'GET /attendance/branches',
    (_) => ok([
      {
        'id': 'b1',
        'name': null,
        'geo_lat': 23.7,
        'geo_lng': 90.4,
        'checkin_radius_m': 100,
        'is_default': true,
      },
      {
        'id': 'b2',
        'name': 'Uttara',
        'geo_lat': null,
        'geo_lng': null,
        'checkin_radius_m': 100,
        'is_default': false,
      },
    ]),
  )
  ..on('PATCH /attendance/setup/sections/sa', (_) => ok(_section('sa', 'A')))
  ..on(
    'POST /attendance/setup/apply',
    (_) => ok({
      'sections': [
        {
          'id': 'sb',
          'name': 'B',
          'class': {'id': 'c6', 'name': 'Class 6'},
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
  app.read(routerProvider).go('/attendance-setup');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

Finder _scrollable() => find
    .descendant(
      of: find.byType(ClassSetupScreen),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _show(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: _scrollable());
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

void main() {
  test('the schedule as lines, days in school-week order', () {
    final lines = periodsOf([
      (day: 1, start: '10:00', end: '10:45', subject: 'M', teacher: 'R'),
      (day: 6, start: '10:00', end: '10:45', subject: 'M', teacher: 'R'),
      (day: 2, start: '09:00', end: '09:45', subject: 'E', teacher: 'J'),
    ]);
    expect(lines, hasLength(2));
    expect(lines.first.start, '09:00');
    expect(lines.last.days, [6, 1]);
  });

  testWidgets('each section: its schedule, branch without a pin, choices', (
    tester,
  ) async {
    await _open(tester, _api());
    expect(find.text('Class 6 A'), findsOneWidget);
    expect(
      find.text('Sat, Mon, Tue 10:00–10:45 · Maths · Rina Akter'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('setup-without')), findsOneWidget);
    expect(find.byKey(const Key('nopin-sa')), findsOneWidget);
    await _show(tester, find.byKey(const Key('setup-sb')));
    expect(find.text(_en.classSetupNoSchedule), findsOneWidget);
  });

  testWidgets('a choice saves at once', (tester) async {
    final api = _api();
    await _open(tester, api);
    await _show(tester, find.byKey(const Key('mode-sa')));
    await tester.tap(find.byKey(const Key('mode-sa')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.classSetupModesPAPERREGISTER).last);
    await tester.pumpAndSettle();
    expect(api.to('PATCH /attendance/setup/sections/sa').single.body, {
      'mode': 'PAPER_REGISTER',
    });
    expect(find.text(_en.classSetupSaved('Class 6 A')), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _show(tester, find.byKey(const Key('grace-sa')));
    await tester.tap(find.byKey(const Key('grace-sa')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.classSetupGraceMinutes(15)).last);
    await tester.pumpAndSettle();
    expect(api.to('PATCH /attendance/setup/sections/sa').last.body, {
      'grace_minutes': 15,
    });
  });

  testWidgets('apply to the class after a preview', (tester) async {
    final api = _api();
    await _open(tester, api);
    await _show(tester, find.byKey(const Key('apply-sa')));
    await tester.tap(find.byKey(const Key('apply-sa')));
    await tester.pumpAndSettle();
    expect(api.to('POST /attendance/setup/apply').single.body, {
      'from_section_id': 'sa',
      'class_id': 'c6',
      'include_schedule': false,
      'include_settings': true,
      'dry_run': true,
    });
    expect(find.text('• Class 6 B'), findsOneWidget);
    await tester.tap(find.byKey(const Key('apply-shift')));
    await tester.pumpAndSettle();
    expect(
      (api.to('POST /attendance/setup/apply').last.body! as Map)['shift'],
      'MORNING',
    );
    await tester.tap(find.byKey(const Key('apply-confirm')));
    await tester.pumpAndSettle();
    final last = api.to('POST /attendance/setup/apply').last.body! as Map;
    expect(last['dry_run'], isFalse);
    expect(find.textContaining('applied to 1'), findsOneWidget);
    expect(find.textContaining('[['), findsNothing);
  });

  testWidgets('read-only rows: no apply, no changes', (tester) async {
    await _open(tester, _api(canManage: false), role: 'TEACHER');
    expect(find.byKey(const Key('apply-sa')), findsNothing);
    expect(find.byKey(const Key('branch-sa')), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.classSetupTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

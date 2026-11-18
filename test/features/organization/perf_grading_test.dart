import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/organization/screens/perf_grading_screens.dart';
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

Map<String, Object?> _weights({bool closed = false}) => {
  'session': {'id': 'se1', 'name': '2026', 'closed': closed},
  'classes': [
    {
      'class': {'id': 'c6', 'name': 'Class 6'},
      'weights': {
        'exams_pct': 60,
        'homework_pct': 20,
        'attendance_pct': 10,
        'behaviour_pct': 10,
      },
      'is_default': true,
    },
  ],
};

Map<String, Object?> _scale({bool custom = false}) => {
  'name': custom ? 'Our scale' : 'Bangladesh',
  'is_custom': custom,
  'bands': [
    {'min_pct': 80, 'max_pct': 100, 'grade': 'A+', 'gpa': 5},
    {'min_pct': 0, 'max_pct': 79.99, 'grade': 'F', 'gpa': 0},
  ],
  'updated_at': '2026-11-01T00:00:00Z',
};

FakeApi _api({bool closed = false, bool custom = false}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on('GET /sessions', (_) => ok(<Object>[]))
  ..on('GET /scores/weights', (_) => ok(_weights(closed: closed)))
  ..on('PUT /scores/weights', (_) => ok(_weights()))
  ..on(
    'GET /scores/settings',
    (_) => ok({
      'at_risk': {'score_pct': 40, 'attendance_pct': 75, 'missing_homework': 3},
      'show_rank': false,
    }),
  )
  ..on('PUT /scores/settings', (r) => ok(r.body))
  ..on('GET /grading-scale', (_) => ok(_scale(custom: custom)))
  ..on('PUT /grading-scale', (_) => ok(_scale(custom: true)))
  ..on('DELETE /grading-scale', (_) => ok(_scale()));

Future<void> _open(
  WidgetTester tester,
  FakeApi api,
  String route, {
  String role = 'OWNER',
  String? lang,
}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _member(role),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go(route);
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

GradeBand _b(double min, double max, String g) =>
    (min: min, max: max, grade: g, gpa: null);

void main() {
  group('grade bands, checked as the API checks them', () {
    test('a whole scale is fine; 79.99 then 80 is no gap', () {
      expect(validateGradeBands([_b(80, 100, 'A'), _b(0, 79.99, 'F')]), isNull);
    });

    test('start at 0, end at 100, no gaps, no twins', () {
      expect(validateGradeBands([])?.code, 'GRADING_SCALE_EMPTY');
      expect(
        validateGradeBands([_b(1, 100, 'A')])?.code,
        'GRADING_SCALE_MUST_START_AT_0',
      );
      expect(
        validateGradeBands([_b(0, 99, 'A')])?.code,
        'GRADING_SCALE_MUST_END_AT_100',
      );
      expect(validateGradeBands([_b(0, 50, 'F'), _b(60, 100, 'A')]), (
        code: 'GRADING_SCALE_GAP_OR_OVERLAP',
        band: 1,
      ));
      expect(
        validateGradeBands([_b(0, 50, 'A'), _b(50.01, 100, 'a')])?.code,
        'GRADING_SCALE_DUPLICATE_GRADE',
      );
      expect(
        validateGradeBands([_b(0, 100, 'TOOLONG')])?.code,
        'GRADING_SCALE_BAND_INVALID',
      );
    });
  });

  testWidgets('weights must add up to 100; then saved for the class', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, '/performance-settings');
    final save = find.byKey(const Key('w-save-c6'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('w-c6-exams_pct')), '50');
    await tester.pump();
    expect(find.text(_en.performanceSettingsMustAddUp), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('w-c6-homework_pct')), '30');
    await tester.pump();
    await _tap(tester, save);
    expect(api.to('PUT /scores/weights').single.body, {
      'session_id': 'se1',
      'class_id': 'c6',
      'exams_pct': 50,
      'homework_pct': 30,
      'attendance_pct': 10,
      'behaviour_pct': 10,
    });
  });

  testWidgets('a closed session: weights read-only', (tester) async {
    await _open(tester, _api(closed: true), '/performance-settings');
    expect(find.byKey(const Key('perf-closed')), findsOneWidget);
    expect(find.byKey(const Key('w-save-c6')), findsNothing);
  });

  testWidgets('at-risk limits and the position', (tester) async {
    final api = _api();
    await _open(tester, api, '/performance-settings');
    await tester.enterText(find.byKey(const Key('risk-missing')), '60');
    await tester.pump();
    expect(find.text(_en.performanceSettingsLimitsInvalid), findsOneWidget);
    await tester.enterText(find.byKey(const Key('risk-missing')), '5');
    await _tap(tester, find.byKey(const Key('show-rank')));
    await _tap(tester, find.byKey(const Key('rules-save')));
    expect(api.to('PUT /scores/settings').single.body, {
      'at_risk': {'score_pct': 40, 'attendance_pct': 75, 'missing_homework': 5},
      'show_rank': true,
    });
  });

  testWidgets('grading scale: a gap is shown and blocks saving', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, '/grading-scale');
    expect(find.text(_en.gradingScaleDefaultName), findsOneWidget);
    await tester.enterText(find.byKey(const Key('band-0-min')), '85');
    await tester.pump();
    expect(find.byKey(const Key('scale-problem')), findsOneWidget);
    final save = find.byKey(const Key('scale-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('band-0-min')), '80');
    await tester.enterText(find.byKey(const Key('scale-name')), 'Our scale');
    await tester.pump();
    await _tap(tester, save);
    final body = api.to('PUT /grading-scale').single.body! as Map;
    expect(body['name'], 'Our scale');
    expect((body['bands'] as List).first, {
      'min_pct': 80.0,
      'max_pct': 100.0,
      'grade': 'A+',
      'gpa': 5.0,
    });
  });

  testWidgets('a custom scale goes back to the default after asking', (
    tester,
  ) async {
    final api = _api(custom: true);
    await _open(tester, api, '/grading-scale');
    await _tap(tester, find.byKey(const Key('scale-reset')));
    expect(find.text(_en.gradingScaleResetTitle), findsOneWidget);
    await tester.tap(find.byKey(const Key('scale-reset-confirm')));
    await tester.pumpAndSettle();
    expect(api.to('DELETE /grading-scale'), hasLength(1));
  });

  testWidgets('teachers read the scale', (tester) async {
    await _open(tester, _api(), '/grading-scale', role: 'TEACHER');
    expect(find.byKey(const Key('scale-read')), findsOneWidget);
    expect(find.byKey(const Key('scale-save')), findsNothing);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), '/grading-scale', lang: 'bn');
    expect(find.text(bn.gradingScaleTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

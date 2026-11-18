import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
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

Map<String, Object?> _hw() => {
  'late_allowed': true,
  'late_penalty': {'type': 'NONE', 'percent': 0},
  'resubmissions': 1,
  'max_files': 5,
};

FakeApi _api() => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on('GET /homework/settings', (_) => ok(_hw()))
  ..on(
    'PATCH /homework/settings',
    (r) => ok({..._hw(), ...(r.body! as Map).cast<String, Object?>()}),
  )
  ..on(
    'GET /integrity/settings',
    (_) => ok({'high': 70, 'medium': 40, 'min_words': 50}),
  )
  ..on('PUT /integrity/settings', (_) => ok(null));

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

Future<void> _pick(WidgetTester tester, String key, String option) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('homework: a penalty needs 1–100 %; save sends all', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, '/homework-settings');
    expect(find.text(_en.homeworkSettingsSummary(1, 5)), findsOneWidget);
    await _pick(tester, 'hw-penalty', _en.homeworkSettingsPenaltiesPERDAY);
    await tester.enterText(find.byKey(const Key('hw-percent')), '150');
    await tester.pump();
    expect(find.text(_en.homeworkSettingsPercentInvalid), findsOneWidget);
    final save = find.byKey(const Key('hw-save'));
    await tester.ensureVisible(save);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('hw-percent')), '10');
    await _pick(tester, 'hw-files', '3');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(api.to('PATCH /homework/settings').single.body, {
      'late_allowed': true,
      'late_penalty': {'type': 'PER_DAY', 'percent': 10},
      'resubmissions': 1,
      'max_files': 3,
    });
    expect(find.text(_en.homeworkSettingsSavedTitle), findsOneWidget);
  });

  testWidgets('homework: no late hand-ins hides the penalty', (tester) async {
    await _open(tester, _api(), '/homework-settings');
    await tester.tap(find.byKey(const Key('hw-late')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hw-penalty')), findsNothing);
  });

  testWidgets('homework: teachers read', (tester) async {
    await _open(tester, _api(), '/homework-settings', role: 'TEACHER');
    expect(find.text(_en.homeworkSettingsReadOnly), findsOneWidget);
    expect(find.byKey(const Key('hw-save')), findsNothing);
  });

  testWidgets('plagiarism: thresholds within limits, then saved', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, '/plagiarism-settings');
    await tester.enterText(find.byKey(const Key('pl-medium')), '100');
    await tester.pump();
    final save = find.byKey(const Key('pl-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('pl-medium')), '45');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(api.to('PUT /integrity/settings').single.body, {
      'high': 70,
      'medium': 45,
      'min_words': 50,
    });
    expect(find.text(_en.plagiarismSettingsSaved), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), '/homework-settings', lang: 'bn');
    expect(find.text(bn.homeworkSettingsTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

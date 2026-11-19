import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/results/screens/school_overview.dart';
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
    'GET /scores/sections',
    (_) => ok({
      'session': {'id': 'se1', 'name': '2026', 'closed': false},
      'terms': [
        {'id': 't1', 'name': 'Term 1'},
      ],
      'sections': [
        {'id': 'sa', 'name': 'A', 'class_name': 'Class 6'},
      ],
    }),
  )
  ..on(
    'GET /scores/overview',
    (_) => ok({
      'sections': [
        {
          'section': {'id': 'sa', 'name': 'A', 'class_name': 'Class 6'},
          'students': 30,
          'average_pct': 62,
          'highest_pct': 95,
          'lowest_pct': 21,
          'attendance_pct': 88,
          'homework_rate_pct': 74,
          'at_risk': 4,
        },
      ],
      'subjects': [
        {
          'subject': {'id': 'm', 'name': 'Mathematics'},
          'average_pct': 58,
          'sections': 3,
        },
      ],
    }),
  )
  ..on(
    'GET /scores/sections/sa',
    (_) => ok({
      'section': {'id': 'sa', 'name': 'A', 'class_name': 'Class 6'},
      'subjects': <Object>[],
      'students': <Object>[],
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
  app.read(routerProvider).go('/performance');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('owners start on the whole school; a section opens', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    expect(find.byType(SchoolOverviewView), findsOneWidget);
    expect(api.to('GET /scores/overview').single.query['session_id'], 'se1');
    expect(find.text('Class 6 A'), findsOneWidget);
    expect(find.text('62%'), findsOneWidget);
    expect(find.text('Mathematics'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('school-open-sa')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('school-open-sa')));
    await tester.pumpAndSettle();
    expect(find.byType(SchoolOverviewView), findsNothing);
    expect(api.to('GET /scores/sections/sa'), isNotEmpty);
  });

  testWidgets('a term asks the overview for that term', (tester) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('perf-term')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Term 1').last);
    await tester.pumpAndSettle();
    expect(api.to('GET /scores/overview').last.query['term_id'], 't1');
  });

  testWidgets('teachers keep the section view', (tester) async {
    await _open(tester, _api(), role: 'TEACHER');
    expect(find.byType(SchoolOverviewView), findsNothing);
    expect(find.text(_en.performanceWholeSchool), findsNothing);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.performanceWholeSchool), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/ielts/data/ielts.dart';
import 'package:instructor_app/features/ielts/screens/ielts_overview_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

/// Someone in an IELTS centre, as [memberRole].
Session ieltsMember(String memberRole) {
  final p = sessionPayload();
  return Session.fromPayload({
    ...p,
    'role': memberRole == 'STUDENT' ? 'STUDENT' : 'TEACHER',
    'workspace_type': 'IELTS',
    'organization': <String, dynamic>{
      ...(p['organization'] as Map<String, dynamic>),
      'name': 'Demo IELTS Centre',
      'role': memberRole,
      'workspace_type': 'IELTS',
    },
  });
}

FakeApi _api({FakeHandler? staff, FakeHandler? me}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on(
    'GET /me/entitlements',
    (_) => ok({
      'features': {'ielts': true},
    }),
  )
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /ielts/dashboard',
    staff ??
        (_) => ok({
          'batches': 3,
          'students': 42,
          'waiting': {'writing': 5, 'speaking': 0},
          'upcoming': [
            {
              'assignment_id': 'a1',
              'test_title': 'Full mock 1',
              'batch': 'Morning batch',
              'opens_at': '2026-11-25T03:00:00.000Z',
              'closes_at': '2026-11-25T07:00:00.000Z',
            },
          ],
          'batch_bands': [
            {
              'section_id': 's1',
              'batch': 'Morning batch',
              'bands': {'LISTENING': 6.5, 'READING': 7, 'WRITING': 6},
            },
          ],
        }),
  )
  ..on(
    'GET /ielts/dashboard/me',
    me ??
        (_) => ok({
          'profile': {
            'target_overall': 7,
            'target_bands': {'WRITING': 6.5},
            'days_to_test': 30,
          },
          'latest': {'LISTENING': 7.5, 'WRITING': 6},
          'open_now': 2,
          'next': {
            'assignment_id': 'a1',
            'test_title': 'Reading practice 3',
            'purpose': 'PRACTICE',
            'opens_at': '2026-11-22T03:00:00.000Z',
            'closes_at': '2026-11-29T03:00:00.000Z',
          },
        }),
  );

Future<void> _open(
  WidgetTester tester,
  FakeApi api,
  String role, {
  String? lang,
}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: ieltsMember(role),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go('/ielts/overview');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

void main() {
  test('bands have one decimal, in the language\'s digits', () {
    expect(bandText(7, 'en'), '7.0');
    expect(bandText(6.5, 'en'), '6.5');
    expect(bandText(6.5, 'bn'), '৬.৫');
    expect(bandText(null, 'en'), '—');
  });

  testWidgets('staff: the centre, marking waiting, mocks and bands', (
    tester,
  ) async {
    await _open(tester, _api(), 'OWNER');
    expect(find.byType(IeltsOverviewScreen), findsOneWidget);
    expect(find.text(_en.ieltsOverviewStaffDescription), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.byKey(const Key('ielts-go-marking')), findsOneWidget);
    expect(find.text('Full mock 1 · Morning batch'), findsOneWidget);
    expect(find.text('6.5'), findsOneWidget);
    expect(find.text('7.0'), findsOneWidget);
    // No band for Speaking yet.
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('a student: targets, latest bands and the next test', (
    tester,
  ) async {
    await _open(tester, _api(), 'STUDENT');
    expect(find.text(_en.ieltsOverviewStudentDescription), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.byKey(const Key('ielts-next')), findsOneWidget);
    // Listening: 7.5 against the overall 7.0 target, reached.
    expect(find.text(_en.ieltsOverviewReached), findsOneWidget);
    // Writing: 6.0 against its own 6.5 target.
    expect(find.text(_en.ieltsOverviewToGo('0.5')), findsOneWidget);
  });

  testWidgets('not an IELTS centre: says so', (tester) async {
    await _open(
      tester,
      _api(staff: (_) => apiError(403, code: 'IELTS_ONLY_CENTRES')),
      'OWNER',
    );
    expect(find.text(_en.ieltsTestsNotAvailable), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), 'OWNER', lang: 'bn');
    expect(find.text(bn.ieltsOverviewTitle), findsWidgets);
    expect(tester.takeException(), isNull);
    await _open(tester, _api(), 'STUDENT', lang: 'bn');
    expect(tester.takeException(), isNull);
  });
}

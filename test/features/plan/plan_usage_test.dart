import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/plan/screens/plan_usage_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Session _owner() {
  final p = sessionPayload();
  return Session.fromPayload({
    ...p,
    'role': 'TEACHER',
    'organization': <String, dynamic>{
      ...(p['organization'] as Map<String, dynamic>),
      'role': 'OWNER',
    },
  });
}

FakeApi _api({bool full = false}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on(
    'GET /me/entitlements',
    (_) => ok({
      'features': <String, bool>{},
      'plan': {'name': 'School Pro', 'slug': 'school-pro'},
      'limits': {'max_exams_per_month': 50, 'max_total_exams': 0},
      'usage': {'exams_used_this_month': 12, 'total_exams_used': 140},
    }),
  )
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /files/usage',
    (_) => ok({
      'used_bytes': full ? 5368709120 : 4831838208,
      'limit_bytes': 5368709120,
      'percent': full ? 100 : 90,
      'warning': true,
      'full': full,
      'by_type': {'homework': 3221225472, 'resources': 1610612736},
    }),
  )
  ..on(
    'GET /sms-credits',
    (_) => ok({
      'total_left': 40,
      'low': true,
      'allowance': {'left': 30, 'granted': 500},
      'top_up': {'left': 10},
    }),
  );

Future<void> _open(WidgetTester tester, FakeApi api, {String? lang}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _owner(),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go('/billing');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

void main() {
  test('file sizes', () {
    expect(fileSize(512, 'en'), '512 B');
    expect(fileSize(1536, 'en'), '1.5 KB');
    expect(fileSize(4831838208, 'en'), '4.5 GB');
    expect(fileSize(10 * 1024 * 1024, 'en'), '10 MB');
  });

  testWidgets('the plan, tests used against its limits', (tester) async {
    await _open(tester, _api());
    expect(find.text(_en.billingCurrentPlan('School Pro')), findsOneWidget);
    expect(find.text(_en.billingUsageOf(12, 50)), findsOneWidget);
    // No limit: the number alone.
    expect(find.text('140'), findsOneWidget);
  });

  testWidgets('storage near full and SMS credits', (tester) async {
    await _open(tester, _api());
    expect(find.text(_en.storageUsed('4.5 GB', '5 GB')), findsOneWidget);
    expect(find.text(_en.storageWarning), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('sms-card')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(_en.smsCreditsTotalLeft(40)), findsOneWidget);
    expect(find.text(_en.smsCreditsLow), findsOneWidget);
    expect(find.text(_en.smsCreditsAllowanceLeft(30, 500)), findsOneWidget);
  });

  testWidgets('view only: nothing to buy, upgrade or top up', (tester) async {
    await _open(tester, _api(full: true));
    expect(find.text(_en.storageFull), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('sms-log')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    for (final s in [
      _en.billingUpgrade,
      _en.billingDowngrade,
      _en.smsCreditsBuy,
      _en.smsCreditsBuyHeading,
      _en.billingSeeFeatures,
    ]) {
      expect(find.text(s), findsNothing);
    }
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.billingTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

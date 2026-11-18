import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/organization/data/log_names.g.dart';
import 'package:instructor_app/features/organization/screens/logs_screens.dart';
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

FakeApi _api() => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /audit-logs',
    (r) => (
      200,
      {
        'payload': [
          {
            'id': 'a1',
            'created_at': '2026-11-18T04:00:00Z',
            'action': 'plan.update',
            'actor': {'full_name': 'Owner Person'},
            'before': {'name': 'Basic', 'active': true},
            'after': {'name': 'Pro', 'active': true},
            'reason': null,
          },
          {
            'id': 'a2',
            'created_at': '2026-11-18T05:00:00Z',
            'action': 'something.new',
            'actor': null,
            'before': null,
            'after': null,
          },
        ],
        'meta': {
          'page': r.query['page'],
          'limit': 20,
          'total': 25,
          'total_pages': 2,
        },
      },
    ),
  )
  ..on(
    'GET /notifications/log',
    (_) => ok([
      {
        'id': 'n1',
        'created_at': '2026-11-18T04:00:00Z',
        'event_type': 'exam.scheduled',
        'channel': 'SMS',
        'status': 'FAILED',
        'recipient': {'id': 'g1', 'full_name': 'Karim Guardian'},
        'to_address': null,
        'subject': null,
        'body': 'Test on Sunday',
        'credits_used': 1,
        'error': 'Number unreachable',
      },
    ]),
  );

Future<void> _open(
  WidgetTester tester,
  FakeApi api,
  String route, {
  String? lang,
}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _owner(),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go(route);
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

void main() {
  test('a day starts at midnight in Dhaka', () {
    expect(dayBoundary('2026-11-18'), '2026-11-17T18:00:00.000Z');
    expect(dayBoundary('2026-11-18', next: true), '2026-11-18T18:00:00.000Z');
    expect(dayBoundary(null), isNull);
  });

  test('names come from the web; unknown keys give null', () {
    expect(auditActionName(_en, 'plan.update'), isNotNull);
    expect(auditActionName(_en, 'something.new'), isNull);
    expect(messageStatusName(_en, 'NO_CREDIT'), isNotNull);
  });

  testWidgets('activity: names, who, what changed; the next page', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, '/activity-log');
    expect(find.text(auditActionName(_en, 'plan.update')!), findsOneWidget);
    // An action the messages do not know shows its key.
    expect(find.text('something.new'), findsOneWidget);
    expect(find.textContaining(_en.auditSystem), findsOneWidget);
    expect(find.textContaining('Basic → Pro'), findsOneWidget);
    await tester.tap(find.byKey(const Key('audit-a1')));
    await tester.pumpAndSettle();
    expect(find.text(_en.auditChanges), findsOneWidget);
    Navigator.of(tester.element(find.text(_en.auditChanges))).pop();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('log-next')));
    await tester.tap(find.byKey(const Key('log-next')));
    await tester.pumpAndSettle();
    expect(api.to('GET /audit-logs').last.query['page'], 2);
  });

  testWidgets('activity: an area filters and starts again', (tester) async {
    final api = _api();
    await _open(tester, api, '/activity-log');
    await tester.tap(find.byKey(const Key('audit-area')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(auditAreaName(_en, 'member')!).last);
    await tester.pumpAndSettle();
    final q = api.to('GET /audit-logs').last.query;
    expect(q['action'], 'member.');
    expect(q['page'], 1);
  });

  testWidgets('messages: status, error, and one recipient', (tester) async {
    final api = _api();
    await _open(tester, api, '/message-log');
    expect(find.text(messageEventName(_en, 'exam.scheduled')!), findsOneWidget);
    expect(find.text(messageStatusName(_en, 'FAILED')!), findsOneWidget);
    expect(find.text('Number unreachable'), findsOneWidget);
    await tester.tap(find.byKey(const Key('msg-to-n1')));
    await tester.pumpAndSettle();
    expect(api.to('GET /notifications/log').last.query['recipient_id'], 'g1');
    expect(find.byKey(const Key('msg-recipient')), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), '/message-log', lang: 'bn');
    expect(find.text(bn.messageLogTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

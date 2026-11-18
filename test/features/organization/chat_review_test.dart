import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/organization/screens/chat_review_screen.dart';
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

const _path = 'chat/admin/chats/GROUP/g1';

FakeApi _api({FakeHandler? chats}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /chat/admin/chats',
    chats ??
        (_) => ok([
          {
            'type': 'GROUP',
            'id': 'g1',
            'label': 'Class 6 A · Maths',
            'closed': false,
            'last_message_at': '2026-11-18T08:00:00Z',
          },
        ]),
  )
  ..on(
    'POST /$_path/open',
    (_) => ok({
      'chat': {'type': 'GROUP', 'id': 'g1', 'label': 'Class 6 A · Maths'},
      'messages': [
        {
          'id': 'm1',
          'group_id': 'g1',
          'author': {'id': 's9', 'name': 'Karim Hasan'},
          'content': 'Rude words',
          'attachments': <Object>[],
          'created_at': '2026-11-18T08:00:00Z',
        },
      ],
    }),
  )
  ..on('DELETE /$_path/messages/m1', (_) => ok(null))
  ..on('POST /$_path/mutes', (_) => ok(null))
  ..on('PUT /$_path/closed', (_) => ok(null))
  ..on(
    'GET /chat/admin/reports',
    (r) => ok(
      r.query['status'] == 'OPEN'
          ? [
              {
                'id': 'r1',
                'chat_label': 'Class 6 A · Maths',
                'reporter': {'name': 'Nadia Islam'},
                'reason': 'Bullying',
                'context': [
                  {
                    'author_name': 'Karim Hasan',
                    'content': 'Rude words',
                    'files': <String>[],
                  },
                ],
                'status': 'OPEN',
              },
            ]
          : <Object>[],
    ),
  )
  ..on('POST /chat/admin/reports/r1/resolve', (_) => ok(null))
  ..on(
    'GET /chat/admin/access-log',
    (_) => ok([
      {
        'id': 'a1',
        'opened_at': '2026-11-18T09:00:00Z',
        'actor': {'name': 'Owner Person'},
        'chat_label': 'Class 6 A · Maths',
        'reason': 'A report',
      },
    ]),
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
  app.read(routerProvider).go('/chat-admin');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('open a chat with a reason; delete, mute, close', (tester) async {
    final api = _api();
    await _open(tester, api);
    expect(find.text('Class 6 A · Maths'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-g1')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const Key('open-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('open-reason')), ' A report ');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(api.to('POST /$_path/open').single.body, {'reason': 'A report'});
    expect(find.byType(OpenedChatScreen), findsOneWidget);
    expect(find.text('Rude words'), findsOneWidget);

    await tester.tap(find.byKey(const Key('rmute-m1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mute-confirm')));
    await tester.pumpAndSettle();
    expect(api.to('POST /$_path/mutes').single.body, {
      'user_id': 's9',
      'hours': 24,
      'reason': '',
    });
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rdelete-m1')));
    await tester.pumpAndSettle();
    expect(api.to('DELETE /$_path/messages/m1'), hasLength(1));
    expect(find.text('Rude words'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-closed')));
    await tester.pumpAndSettle();
    expect(api.to('PUT /$_path/closed').single.body, {'closed': true});
  });

  testWidgets('reports: keep or delete', (tester) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(find.text(_en.chatReviewReports));
    await tester.pumpAndSettle();
    expect(
      find.text(_en.chatReviewReportedBy('Nadia Islam', 'Bullying')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('delete-msg-r1')));
    await tester.pumpAndSettle();
    expect(api.to('POST /chat/admin/reports/r1/resolve').single.body, {
      'resolution': 'DELETED',
    });
  });

  testWidgets('the access log is for owners', (tester) async {
    await _open(tester, _api());
    await tester.tap(find.text(_en.chatReviewAccessLog));
    await tester.pumpAndSettle();
    expect(find.text('Owner Person · Class 6 A · Maths'), findsOneWidget);
  });

  testWidgets('admins: no access log; 403 says not allowed', (tester) async {
    await _open(
      tester,
      _api(chats: (_) => apiError(403, code: 'FORBIDDEN')),
      role: 'ADMIN',
    );
    expect(find.text(_en.chatReviewAccessLog), findsNothing);
    expect(find.text(_en.chatReviewNotAllowed), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.chatReviewTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

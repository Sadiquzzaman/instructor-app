import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/features/notifications/data/notifications_repository.dart';
import 'package:instructor_app/features/notifications/screens/inbox_screen.dart';
import 'package:instructor_app/features/notifications/state/unread_count.dart';
import 'package:instructor_app/features/shell/screens/home_screen.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

Map<String, Object?> _item(
  String id, {
  bool read = false,
  String? link,
  String title = 'New test',
}) => {
  'id': id,
  'type': 'exam.published',
  'title': '$title $id',
  'body': 'Opens tomorrow',
  'link': link,
  'read_at': read ? '2026-11-17T08:00:00.000Z' : null,
  'created_at': '2026-11-17T06:30:00.000Z',
  'organization_id': 'org-1',
};

FakeApi _api({
  int unread = 2,
  List<Map<String, Object?>>? page1,
  List<Map<String, Object?>>? page2,
}) {
  final first = page1 ?? [_item('n1'), _item('n2'), _item('n3', read: true)];
  return FakeApi()
    ..on('GET /auth/contexts', (_) => ok(<Object>[]))
    ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
    ..on('GET /me/notifications/unread-count', (_) => ok({'count': unread}))
    ..on('GET /me/notifications', (r) {
      final page = (r.query['page'] as int?) ?? 1;
      final items = page == 1 ? first : (page2 ?? const []);
      return ok(
        items,
        meta: {
          'page': page,
          'limit': 20,
          'total': first.length + (page2?.length ?? 0),
          'total_pages': page2 == null ? 1 : 2,
          'unread': unread,
        },
      );
    })
    ..on('PATCH /me/notifications/n1/read', (_) => ok({'id': 'n1'}))
    ..on('POST /me/notifications/read-all', (_) => ok({'updated': 2}));
}

Future<void> _openInbox(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('notification-bell')));
  await tester.pumpAndSettle();
}

void main() {
  test('InboxItem reads the API answer', () {
    final i = InboxItem.fromJson(_item('n1', link: '/tests/abc'))!;
    expect(i.title, 'New test n1');
    expect(i.unread, isTrue);
    expect(i.link, '/tests/abc');
    expect(InboxItem.fromJson({'id': 'x'}), isNull);
    expect(i.markedRead(DateTime.utc(2026)).unread, isFalse);
  });

  test('only pages the app has built open from a notification', () {
    expect(AppRoutes.isAppPage('/notifications'), isTrue);
    expect(AppRoutes.isAppPage('/'), isTrue);
    expect(AppRoutes.isAppPage('/tests/abc'), isFalse);
    expect(AppRoutes.isAppPage('https://example.com/'), isFalse);
  });

  testWidgets('the bell shows the unread count and says it', (tester) async {
    await pumpInstructorApp(
      tester,
      api: _api(unread: 3),
      session: testSession(),
    );
    expect(find.text('3'), findsOneWidget);
    expect(find.byTooltip('Notifications, 3 unread'), findsOneWidget);
    // Screen readers hear "Notifications, 3 unread", not just "3".
    final semantics = tester.ensureSemantics();
    final data = tester
        .getSemantics(find.byKey(const Key('notification-bell')))
        .getSemanticsData();
    expect(data.tooltip, 'Notifications, 3 unread');
    expect(data.label, isNot(contains('3')));
    semantics.dispose();
  });

  testWidgets('Bangla digits on the badge', (tester) async {
    await pumpInstructorApp(
      tester,
      api: _api(unread: 3),
      session: testSession(),
      prefs: {'language': 'bn'},
    );
    expect(find.text('৩'), findsOneWidget);
  });

  testWidgets('the badge refreshes every minute; nothing while signed out', (
    tester,
  ) async {
    final api = _api();
    await pumpInstructorApp(tester, api: api, session: testSession());
    final before = api.to('GET /me/notifications/unread-count').length;
    await tester.pump(UnreadCount.pollEvery);
    await tester.pumpAndSettle();
    expect(api.to('GET /me/notifications/unread-count').length, before + 1);

    final signedOut = _api();
    await pumpInstructorApp(tester, api: signedOut);
    await tester.pump(UnreadCount.pollEvery);
    expect(signedOut.to('GET /me/notifications/unread-count'), isEmpty);
  });

  testWidgets('inbox: items, open one marks it read and lowers the badge', (
    tester,
  ) async {
    final api = _api();
    final container = await pumpInstructorApp(
      tester,
      api: api,
      session: testSession(),
    );
    await _openInbox(tester);
    expect(find.byType(InboxScreen), findsOneWidget);
    expect(find.text('New test n1'), findsOneWidget);
    expect(find.text('New test n3'), findsOneWidget);
    // 06:30 UTC is 12:30 in Dhaka.
    expect(find.text('17 Nov 2026, 12:30'), findsNWidgets(3));

    await tester.tap(find.text('New test n1'));
    await tester.pumpAndSettle();
    expect(api.to('PATCH /me/notifications/n1/read'), hasLength(1));
    expect(container.read(unreadCountProvider), 1);
    // A link to a page the app does not have yet: stay in the inbox.
    expect(find.byType(InboxScreen), findsOneWidget);
  });

  testWidgets('a link to a page the app has opens it', (tester) async {
    final api = _api(page1: [_item('n1', link: '/')]);
    await pumpInstructorApp(tester, api: api, session: testSession());
    await _openInbox(tester);
    await tester.tap(find.text('New test n1'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('mark all as read', (tester) async {
    final api = _api();
    final container = await pumpInstructorApp(
      tester,
      api: api,
      session: testSession(),
    );
    await _openInbox(tester);
    await tester.tap(find.text('Mark all as read'));
    await tester.pumpAndSettle();
    expect(api.to('POST /me/notifications/read-all'), hasLength(1));
    expect(container.read(unreadCountProvider), 0);
    expect(find.text('Mark all as read'), findsNothing);
  });

  testWidgets('more items load when scrolling to the end', (tester) async {
    final api = _api(
      page1: [for (var i = 0; i < 20; i++) _item('a$i')],
      page2: [_item('b1')],
    );
    await pumpInstructorApp(tester, api: api, session: testSession());
    await _openInbox(tester);
    await tester.scrollUntilVisible(
      find.text('New test b1'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('New test b1'), findsOneWidget);
    expect(
      api.to('GET /me/notifications').map((r) => r.query['page']),
      containsAll([1, 2]),
    );
  });

  testWidgets('no notifications yet', (tester) async {
    await pumpInstructorApp(
      tester,
      api: _api(unread: 0, page1: const []),
      session: testSession(),
    );
    await _openInbox(tester);
    expect(find.text('No notifications yet'), findsOneWidget);
  });

  testWidgets('the inbox cannot load: try again', (tester) async {
    var calls = 0;
    final api = _api()
      ..on('GET /me/notifications', (_) {
        calls++;
        return calls == 1
            ? apiError(502)
            : ok(
                [_item('n1')],
                meta: {
                  'page': 1,
                  'limit': 20,
                  'total': 1,
                  'total_pages': 1,
                  'unread': 1,
                },
              );
      });
    await pumpInstructorApp(tester, api: api, session: testSession());
    await _openInbox(tester);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('New test n1'), findsOneWidget);
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/chat/data/chat.dart';
import 'package:instructor_app/features/chat/screens/chat_screens.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

class _Live implements ChatLive {
  final _c = StreamController<ChatEvent>.broadcast();
  void send(ChatEvent e) => _c.add(e);
  @override
  Stream<ChatEvent> get events => _c.stream;
  @override
  void dispose() {}
}

Map<String, Object?> _msg(
  String id, {
  String author = 'u2',
  String name = 'Karim Uddin',
  String content = 'Hello class',
  String chat = 'g1',
}) => {
  'id': id,
  'group_id': chat,
  'parent_id': null,
  'author': {'id': author, 'name': name, 'is_teacher': author == 'u2'},
  'content': content,
  'attachments': <Object>[],
  'reply_to': null,
  'comment_count': 1,
  'last_comment_at': null,
  'pinned': false,
  'deleted': false,
  'created_at': '2026-11-17T08:00:00Z',
};

FakeApi _api({bool announcementOnly = false, bool teacher = false}) {
  var pinned = false;
  var onlyTeachers = announcementOnly;
  return FakeApi()
    ..on('GET /auth/contexts', (_) => ok(<Object>[]))
    ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
    ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
    ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
    ..on('GET /calendar/me', (_) => ok({'items': <Object>[]}))
    ..on(
      'GET /chat/groups',
      (_) => ok([
        {
          'id': 'g1',
          'class_id': 'c1',
          'section_label': 'Class 6 A',
          'subject': {'id': 'e', 'name': 'English'},
          'role': 'STUDENT',
          'announcement_only': announcementOnly,
          'read_only': false,
          'muted': false,
          'unread': 2,
          'teachers': [
            {'id': 'u2', 'name': 'Karim Uddin'},
          ],
          'last_message': {
            'author_name': 'Karim Uddin',
            'preview': 'Hello class',
            'created_at': '2026-11-17T08:00:00Z',
          },
        },
      ]),
    )
    ..on('GET /chat/direct', (_) => ok(<Object>[]))
    ..on(
      'GET /chat/direct/contacts',
      (_) => ok([
        {
          'id': 'u2',
          'name': 'Karim Uddin',
          'via': ['Class 6 A · English'],
        },
      ]),
    )
    ..on(
      'POST /chat/direct',
      (_) => ok({
        'id': 'd1',
        'other': {'id': 'u2', 'name': 'Karim Uddin', 'is_teacher': true},
        'unread': 0,
        'closed': false,
        'muted': false,
      }),
    )
    ..on('GET /chat/direct/d1/messages', (_) => ok(<Object>[]))
    ..on('POST /chat/direct/d1/read', (_) => ok(null))
    ..on(
      'POST /chat/direct/d1/messages',
      (_) => ok(
        _msg(
          'm9',
          author: 'user-1',
          name: 'Test Student',
          content: 'Sir, a question',
          chat: 'd1',
        ),
      ),
    )
    ..on(
      'GET /chat/groups/g1',
      (_) => ok({
        'id': 'g1',
        'label': 'Class 6 A · English',
        'class_id': 'c1',
        'role': teacher ? 'TEACHER' : 'STUDENT',
        'announcement_only': onlyTeachers,
        'read_only': false,
        'closed': false,
        'muted': false,
        'teachers': [
          {'id': 'u2', 'name': 'Karim Uddin'},
        ],
        'pinned': [
          if (pinned) {..._msg('m1'), 'pinned': true},
        ],
      }),
    )
    ..on('PUT /chat/groups/g1/messages/m1/pin', (r) {
      pinned = (r.body as Map)['pinned'] == true;
      return ok({
        'pinned_ids': [if (pinned) 'm1'],
      });
    })
    ..on('PATCH /chat/groups/g1', (r) {
      onlyTeachers = (r.body as Map)['announcement_only'] == true;
      return ok(null);
    })
    ..on(
      'GET /chat/groups/g1/messages',
      (_) => ok([
        _msg('m1'),
        _msg('m0', author: 'user-1', name: 'Test Student', content: 'Mine'),
      ]),
    )
    ..on('POST /chat/groups/g1/read', (_) => ok(null))
    ..on(
      'POST /chat/groups/g1/messages',
      (r) => ok(
        _msg(
          'm2',
          author: 'user-1',
          name: 'Test Student',
          content: '${(r.body! as Map)['content']}',
        ),
      ),
    )
    ..on('DELETE /chat/groups/g1/messages/m0', (_) => ok(null))
    ..on('PUT /chat/groups/g1/mute', (_) => ok(null))
    ..on('POST /chat/reports', (_) => ok(null))
    ..on(
      'GET /chat/groups/g1/messages/m1/comments',
      (_) => ok([_msg('k1', author: 'u3', name: 'Rahim', content: 'Thanks!')]),
    );
}

Future<(FakeApi, _Live)> _open(
  WidgetTester tester, {
  bool announcementOnly = false,
  bool teacher = false,
}) async {
  final live = _Live();
  final api = _api(announcementOnly: announcementOnly, teacher: teacher);
  final c = await pumpInstructorApp(
    tester,
    api: api,
    session: teacher
        ? Session.fromPayload({...sessionPayload(), 'role': 'TEACHER'})
        : testSession(),
    overrides: [chatLiveProvider.overrideWithValue(live)],
  );
  c.read(routerProvider).go(AppRoutes.chat);
  await tester.pumpAndSettle();
  return (api, live);
}

Future<void> _openGroup(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('group-g1')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('class chats with unread; a chat opens, is read, posts', (
    tester,
  ) async {
    final (api, _) = await _open(tester);
    expect(find.text('English · Class 6 A'), findsOneWidget);
    expect(find.text(_en.chatUnread(2)), findsOneWidget);
    await _openGroup(tester);
    expect(find.byType(ChatThreadScreen), findsOneWidget);
    expect(find.text('Hello class'), findsOneWidget);
    expect(api.to('POST /chat/groups/g1/read'), hasLength(1));

    await tester.enterText(
      find.byKey(const Key('chat-text')),
      '  Is it chapter 3?  ',
    );
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    expect(api.to('POST /chat/groups/g1/messages').single.body, {
      'content': 'Is it chapter 3?',
      'file_ids': <String>[],
    });
    expect(find.text('Is it chapter 3?'), findsOneWidget);
  });

  testWidgets('delete my own; report another\'s; mute', (tester) async {
    final (api, _) = await _open(tester);
    await _openGroup(tester);
    expect(find.byKey(const Key('delete-m1')), findsNothing);
    await tester.tap(find.byKey(const Key('delete-m0')));
    await tester.pumpAndSettle();
    expect(api.to('DELETE /chat/groups/g1/messages/m0'), hasLength(1));
    expect(find.text(_en.chatDeleted), findsOneWidget);

    await tester.tap(find.byKey(const Key('report-m1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('report-reason')), 'Rude');
    await tester.tap(find.text(_en.chatReportSend).last);
    await tester.pumpAndSettle();
    expect(api.to('POST /chat/reports').single.body, {
      'chat_type': 'GROUP',
      'chat_id': 'g1',
      'message_id': 'm1',
      'reason': 'Rude',
    });

    await tester.tap(find.byKey(const Key('mute')));
    await tester.pumpAndSettle();
    expect(api.to('PUT /chat/groups/g1/mute').single.body, {'muted': true});
  });

  testWidgets('comments on a post', (tester) async {
    final (api, _) = await _open(tester);
    await _openGroup(tester);
    await tester.tap(find.byKey(const Key('comments-m1')));
    await tester.pumpAndSettle();
    expect(find.text('Thanks!'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('comment-text')), 'Me too');
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    expect(api.to('POST /chat/groups/g1/messages').single.body, {
      'content': 'Me too',
      'file_ids': <String>[],
      'parent_id': 'm1',
    });
  });

  testWidgets('only teachers post: the composer says so', (tester) async {
    await _open(tester, announcementOnly: true);
    await _openGroup(tester);
    expect(find.text(_en.chatTeachersOnly), findsOneWidget);
    expect(find.byKey(const Key('chat-text')), findsNothing);
  });

  testWidgets('a new message arrives live', (tester) async {
    final (_, live) = await _open(tester);
    await _openGroup(tester);
    live.send(
      ChatNewMessage(
        ChatMessage.fromJson(_msg('m5', content: 'Test tomorrow'))!,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test tomorrow'), findsOneWidget);
  });

  testWidgets('private: message a teacher', (tester) async {
    final (api, _) = await _open(tester);
    await tester.tap(find.text(_en.chatPrivateChats));
    await tester.pumpAndSettle();
    expect(find.text(_en.chatNoPrivate), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-message')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact-u2')));
    await tester.pumpAndSettle();
    expect(api.to('POST /chat/direct').single.body, {'user_id': 'u2'});
    await tester.enterText(
      find.byKey(const Key('chat-text')),
      'Sir, a question',
    );
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    expect(find.text('Sir, a question'), findsOneWidget);
    // Private chats are text only here, as on the web.
    expect(find.byKey(const Key('attach')), findsNothing);
  });
  testWidgets('teachers: the chat list, not the website', (tester) async {
    await _open(tester, teacher: true);
    expect(find.text(_en.appNotYetBody), findsNothing);
    expect(find.byKey(const Key('group-g1')), findsOneWidget);
  });

  testWidgets('teachers post when only teachers can, and switch it off', (
    tester,
  ) async {
    final (api, _) = await _open(tester, announcementOnly: true, teacher: true);
    await _openGroup(tester);
    expect(find.text(_en.chatTeachersOnly), findsNothing);
    expect(find.byKey(const Key('chat-text')), findsOneWidget);
    await tester.tap(find.byKey(const Key('announcement-only')));
    await tester.pumpAndSettle();
    expect(api.to('PATCH /chat/groups/g1').single.body, {
      'announcement_only': false,
    });
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('announcement-only')))
          .value,
      isFalse,
    );
  });

  testWidgets("teachers pin a post and delete anyone's", (tester) async {
    final (api, _) = await _open(tester, teacher: true);
    await _openGroup(tester);
    expect(find.text(_en.chatPinned), findsNothing);
    await tester.tap(find.byKey(const Key('pin-m1')));
    await tester.pumpAndSettle();
    expect(api.to('PUT /chat/groups/g1/messages/m1/pin').single.body, {
      'pinned': true,
    });
    expect(find.text(_en.chatPinned), findsOneWidget);
    expect(find.text(_en.chatUnpin), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-m1')));
    await tester.pumpAndSettle();
    expect(api.to('DELETE /chat/groups/g1/messages/m1'), hasLength(1));
  });

  testWidgets('students do not pin or switch', (tester) async {
    await _open(tester);
    await _openGroup(tester);
    expect(find.byKey(const Key('pin-m1')), findsNothing);
    expect(find.byKey(const Key('announcement-only')), findsNothing);
  });
}

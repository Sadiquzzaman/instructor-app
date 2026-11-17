import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/files/file_uploader.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/classes/data/discussions.dart';
import 'package:instructor_app/features/classes/screens/classes_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();
const _scope = '/classes/c1/subjects/s1';

Map<String, Object?> _post(
  String id, {
  String author = 'user-1',
  int comments = 1,
}) => {
  'id': id,
  'content': 'When is the test?',
  'category': 'question',
  'attachments': [
    {
      'id': 'f9',
      'key': 'f9',
      'url': '/files/f9/content',
      'file_name': 'notes.pdf',
      'mime_type': 'application/pdf',
      'size': 10,
      'kind': 'file',
    },
  ],
  'created_at': '2026-11-17T08:00:00Z',
  'updated_at': null,
  'comments_count': comments,
  'author': {
    'id': author,
    'name': author == 'user-1' ? 'Test Student' : 'Rahim',
  },
  'class_subject': {'id': 's1'},
};

Object _page(List<Object> items) => {
  'items': items,
  'meta': {'page': 1, 'limit': 20, 'total': items.length, 'total_pages': 1},
};

FakeApi _api({FakeHandler? subjects, FakeHandler? conversations}) {
  var conversationsMade = false;
  return FakeApi()
    ..on('GET /auth/contexts', (_) => ok(<Object>[]))
    ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
    ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
    ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
    ..on('GET /calendar/me', (_) => ok({'items': <Object>[]}))
    ..on(
      'GET /student/classes/c1',
      (_) =>
          ok({'id': 'c1', 'class_name': 'Class 6', 'classmates': <Object>[]}),
    )
    ..on(
      'GET /classes/c1/discussion-subjects',
      subjects ??
          (_) => ok([
            {
              'id': 's1',
              'class_subject': {
                'id': 's1',
                'subject': {'id': 'e', 'name': 'English', 'code': 'ENG'},
              },
              'teachers': [
                {'id': 't1', 'name': 'Karim Uddin'},
              ],
            },
          ]),
    )
    ..on(
      'GET $_scope/discussions',
      (r) => ok(
        _page([
          if (r.query['category'] == null)
            _post('p2', author: 'other', comments: 0),
          _post('p1'),
        ]),
      ),
    )
    ..on('POST $_scope/discussions', (_) => ok({'id': 'p3'}))
    ..on('DELETE $_scope/discussions/p1', (_) => ok(null))
    ..on(
      'GET $_scope/discussions/p1/comments',
      (_) => ok(
        _page([
          {
            'id': 'k1',
            'content': 'Next week',
            'created_at': '2026-11-17T09:00:00Z',
            'author': {'id': 't1', 'name': 'Karim Uddin'},
          },
        ]),
      ),
    )
    ..on('POST $_scope/discussions/p1/comments', (_) => ok({'id': 'k2'}))
    ..on(
      'GET $_scope/private-conversations',
      conversations ??
          (_) => ok([
            if (conversationsMade)
              {
                'id': 'v1',
                'student': {'id': 'user-1', 'name': 'Test Student'},
                'teacher': {'id': 't1', 'name': 'Karim Uddin'},
              },
          ]),
    )
    ..on('POST $_scope/private-conversations', (_) {
      conversationsMade = true;
      return ok({
        'id': 'v1',
        'student': {'id': 'user-1', 'name': 'Test Student'},
        'teacher': {'id': 't1', 'name': 'Karim Uddin'},
      });
    })
    ..on(
      'GET $_scope/private-conversations/v1/messages',
      (_) => ok(
        _page([
          {
            'id': 'm1',
            'content': 'Hello sir',
            'attachments': <Object>[],
            'created_at': '2026-11-17T10:00:00Z',
            'sender': {'id': 'user-1', 'name': 'Test Student'},
          },
        ]),
      ),
    )
    ..on(
      'POST $_scope/private-conversations/v1/messages',
      (_) => ok({'id': 'm2'}),
    );
}

Future<void> _openDiscussions(WidgetTester tester, FakeApi api) async {
  final c = await pumpInstructorApp(tester, api: api, session: testSession());
  c.read(routerProvider).go('${AppRoutes.classes}/details/c1');
  await tester.pumpAndSettle();
  await tester.tap(find.text(_en.classesTabsDiscussions));
  await tester.pumpAndSettle();
}

Finder _scrollable() => find
    .descendant(
      of: find.byType(ClassDetailScreen),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: _scrollable());
  await tester.pumpAndSettle();
}

/// Lets the 20-second refresh timers run out before the test ends.
Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 21));
}

void main() {
  test('subjects, posts and what a post sends for a file', () {
    final s = DiscussionSubject.fromJson({
      'id': 's1',
      'class_subject': {
        'subject': {'name': 'English', 'code': 'ENG'},
      },
      'teachers': [
        {'id': 't', 'name': 'K'},
      ],
    })!;
    expect(s.label, 'English — ENG');
    expect(s.teachers.single.name, 'K');
    expect(DiscussionPost.fromJson(_post('p'))!.files.single.name, 'notes.pdf');
    expect(
      DiscussionFile.toJson(
        const UploadedFile(id: 'f', name: 'a.jpg', mime: 'image/jpeg', size: 3),
      ),
      {
        'id': 'f',
        'key': 'f',
        'url': '/files/f/content',
        'file_name': 'a.jpg',
        'mime_type': 'image/jpeg',
        'size': 3,
        'kind': 'image',
      },
    );
  });

  testWidgets('the class discussion: posts, a type filter, a new post', (
    tester,
  ) async {
    final api = _api();
    await _openDiscussions(tester, api);
    expect(find.text('English — ENG'), findsOneWidget);
    expect(find.text('When is the test?'), findsNWidgets(2));
    expect(find.text('notes.pdf'), findsNWidgets(2));

    await _scrollTo(tester, find.text(_en.discussionsFilterQuestion));
    await tester.tap(find.text(_en.discussionsFilterQuestion));
    await tester.pumpAndSettle();
    expect(
      api.to('GET $_scope/discussions').last.query['category'],
      'question',
    );
    expect(find.text('When is the test?'), findsOneWidget);

    await _scrollTo(tester, find.byKey(const Key('post-content')));
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('post-content')),
        matching: find.byType(TextField),
      ),
      '  Shall we revise?  ',
    );
    await _scrollTo(tester, find.byKey(const Key('post-submit')));
    await tester.tap(find.byKey(const Key('post-submit')));
    await tester.pumpAndSettle();
    expect(api.to('POST $_scope/discussions').single.body, {
      'content': 'Shall we revise?',
      'category': 'general',
      'attachments': <Object>[],
    });
    await _end(tester);
  });

  testWidgets('replies: open them, write one; delete my own post', (
    tester,
  ) async {
    final api = _api();
    await _openDiscussions(tester, api);
    final post = find.byKey(const Key('post-p1'));
    await _scrollTo(tester, post);
    await tester.tap(
      find.descendant(
        of: post,
        matching: find.text(_en.discussionsPostComments(1)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Next week'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('reply-p1')),
        matching: find.byType(TextField),
      ),
      'Thanks',
    );
    await tester.ensureVisible(
      find.descendant(
        of: post,
        matching: find.byTooltip(_en.discussionsPostReply),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: post,
        matching: find.byTooltip(_en.discussionsPostReply),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.to('POST $_scope/discussions/p1/comments').single.body, {
      'content': 'Thanks',
    });

    // Only my own post can be deleted, after asking.
    expect(
      find.descendant(
        of: find.byKey(const Key('post-p2')),
        matching: find.byTooltip(_en.discussionsPostDelete),
      ),
      findsNothing,
    );
    await tester.ensureVisible(
      find.descendant(
        of: post,
        matching: find.byTooltip(_en.discussionsPostDelete),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: post,
        matching: find.byTooltip(_en.discussionsPostDelete),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(TextButton, _en.discussionsPostDelete),
    );
    await tester.pumpAndSettle();
    expect(api.to('DELETE $_scope/discussions/p1'), hasLength(1));
    await _end(tester);
  });

  testWidgets('private messages: start with the teacher, send', (tester) async {
    final api = _api();
    await _openDiscussions(tester, api);
    await tester.tap(find.text(_en.discussionsPrivate));
    await tester.pumpAndSettle();
    expect(find.text(_en.discussionsChatNone), findsOneWidget);
    await _scrollTo(tester, find.byKey(const Key('chat-start')));
    await tester.tap(find.byKey(const Key('chat-start')));
    await tester.pumpAndSettle();
    expect(api.to('POST $_scope/private-conversations').single.body, {
      'teacher_id': 't1',
    });
    expect(find.text('Hello sir'), findsOneWidget);

    await _scrollTo(tester, find.byKey(const Key('chat-message')));
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('chat-message')),
        matching: find.byType(TextField),
      ),
      'Is it chapter 3?',
    );
    await _scrollTo(tester, find.byKey(const Key('chat-send')));
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    expect(
      api.to('POST $_scope/private-conversations/v1/messages').single.body,
      {'content': 'Is it chapter 3?', 'attachments': <Object>[]},
    );
    await _end(tester);
  });

  testWidgets('no access to this class\'s discussions says so', (tester) async {
    await _openDiscussions(
      tester,
      _api(subjects: (_) => apiError(403, code: 'FORBIDDEN')),
    );
    expect(
      find.textContaining('do not have access to discussions'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 1));
  });
}

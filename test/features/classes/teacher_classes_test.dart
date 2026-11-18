import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/classes/data/teacher_classes.dart';
import 'package:instructor_app/features/classes/screens/teacher_classes_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

/// A solo teacher in their own workspace (can create classes).
Session _solo() => Session.fromPayload({
  ...sessionPayload(organizationId: null),
  'role': 'TEACHER',
});

/// A teacher in a school (classes come from the school's setup).
Session _school() =>
    Session.fromPayload({...sessionPayload(), 'role': 'TEACHER'});

Map<String, Object?> _member(
  String studentId,
  String status, {
  String? name,
  String? email,
  String? phone,
  String? invitedPhone,
  String? publicId,
  Map<String, Object?>? section,
}) => {
  'id': 'cs-$studentId',
  'class_id': 'c1',
  'student_id': studentId,
  'status': status,
  'student': {
    'id': studentId,
    'full_name': name,
    'email': email,
    'phone': phone,
    'student_public_id': publicId,
  },
  'invited_email': null,
  'invited_phone': invitedPhone,
  'joined_at': status == 'JOINED' ? '2026-11-01T04:00:00.000Z' : null,
  'section': section,
};

Map<String, Object?> _class({List<Object>? members}) => {
  'id': 'c1',
  'class_name': 'Class 9A – Mathematics',
  'description': 'Mathematics for class 9',
  'total_test_taken': 3,
  'last_test_taken_date': '2026-11-10T04:00:00.000Z',
  'classStudents':
      members ??
      [
        _member(
          's1',
          'JOINED',
          name: 'Karim Hasan',
          email: 'karim@example.com',
          publicId: '123456',
          section: {'id': 'sa', 'name': 'A'},
        ),
        _member(
          's2',
          'INVITED',
          invitedPhone: '01000000000',
          section: {'id': 'sb', 'name': 'B'},
        ),
        _member(
          's3',
          'PENDING',
          name: 'Nadia Islam',
          email: 'nadia@example.com',
        ),
      ],
};

FakeApi _api({List<Object>? classes, FakeHandler? one}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /classes',
    (_) => ok(
      classes ??
          [
            _class(),
            {
              ..._class(members: []),
              'id': 'c2',
              'class_name': 'Class 10B – Physics',
              'last_test_taken_date': null,
            },
          ],
    ),
  )
  ..on('GET /classes/c1', one ?? (_) => ok(_class()))
  ..on('POST /classes/c1/students/s3/approve', (_) => ok(<String, Object>{}))
  ..on('DELETE /classes/c1/students', (_) => ok(<String, Object>{}))
  ..on('POST /classes/c1/students', (_) => ok(_class()))
  ..on('POST /classes', (_) => ok({..._class(members: []), 'id': 'c9'}));

Future<void> _open(
  WidgetTester tester,
  FakeApi api,
  String route, {
  Session? session,
  String? lang,
}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: session ?? _solo(),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go(route);
  await tester.pumpAndSettle();
  // A class's page sits on the list's page, whose request answers a tick
  // later.
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

Finder _scrollable() => find.byType(Scrollable).first;

void main() {
  group('inviteProblem (the web\'s checks)', () {
    test('emails, 11-digit phones and Student IDs pass', () {
      expect(inviteProblem('a@b.co'), isNull);
      expect(inviteProblem('01000000000'), isNull);
      expect(inviteProblem('123456'), isNull);
    });
    test('the rest say why', () {
      expect(inviteProblem('a@b'), 'email');
      expect(inviteProblem('0100'), 'phone');
      expect(inviteProblem('abc'), 'input');
    });
  });

  testWidgets('the list: classes with students and tests; search', (
    tester,
  ) async {
    await _open(tester, _api(), '/classes');
    expect(find.byType(TeacherClassesScreen), findsOneWidget);
    expect(find.text('Class 9A – Mathematics'), findsOneWidget);
    expect(find.text('${_en.classesStudents}: 3'), findsOneWidget);
    expect(find.text('${_en.classesTestsTaken}: 3'), findsWidgets);
    expect(find.text(_en.classesNoTestYet), findsOneWidget);
    await tester.enterText(find.byKey(const Key('classes-search')), 'physics');
    await tester.pump();
    expect(find.byKey(const Key('class-c1')), findsNothing);
    expect(find.byKey(const Key('class-c2')), findsOneWidget);
  });

  testWidgets('in a school, no Create class (classes come from the setup)', (
    tester,
  ) async {
    await _open(tester, _api(), '/classes', session: _school());
    expect(find.byKey(const Key('create-class')), findsNothing);
  });

  testWidgets('create a class with students; then its join link', (
    tester,
  ) async {
    final api = _api(classes: []);
    await _open(tester, api, '/classes');
    await tester.tap(find.byKey(const Key('create-class')));
    await tester.pumpAndSettle();
    expect(find.byType(CreateClassScreen), findsOneWidget);

    // A name is needed.
    await tester.tap(find.byKey(const Key('create-save')));
    await tester.pumpAndSettle();
    expect(api.to('POST /classes'), isEmpty);

    await tester.enterText(find.byKey(const Key('class-name')), ' Class 9A ');
    await tester.enterText(find.byKey(const Key('invite-input')), '0100');
    await tester.tap(find.byKey(const Key('invite-add')));
    await tester.pump();
    expect(find.text(_en.classesToastInvalidPhone), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('invite-input')),
      'Karim@Example.com',
    );
    await tester.tap(find.byKey(const Key('invite-add')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('invite-input')),
      'karim@example.com',
    );
    await tester.tap(find.byKey(const Key('invite-add')));
    await tester.pump();
    expect(find.text(_en.classesToastDuplicate), findsOneWidget);
    await tester.enterText(find.byKey(const Key('invite-input')), '123456');
    await tester.tap(find.byKey(const Key('invite-add')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('create-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-save')));
    await tester.pumpAndSettle();
    expect(api.to('POST /classes').single.body, {
      'class_name': 'Class 9A',
      'description': '',
      'students': ['karim@example.com', '123456'],
    });
    // The new class's join link, ready to copy.
    expect(
      find.text(
        _en.classesShareModalCreatedDetail('Class 9A – Mathematics', 2),
      ),
      findsOneWidget,
    );
    expect(find.text(classJoinLink('c9')), findsOneWidget);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    await tester.tap(find.byKey(const Key('share-copy')));
    await tester.pumpAndSettle();
    expect(copied, classJoinLink('c9'));
  });

  testWidgets('a class: who asked to join, then members', (tester) async {
    await _open(tester, _api(), '/classes/details/c1');
    expect(find.byType(TeacherClassScreen), findsOneWidget);
    expect(find.text(_en.classesRosterPending(1)), findsOneWidget);
    expect(find.text(_en.classesRosterActive(2)), findsOneWidget);
    expect(find.byKey(const Key('approve-s3')), findsOneWidget);
    // No name yet: their contact.
    expect(find.text('01000000000'), findsWidgets);
    // Joined before invited.
    double y(String id) => tester.getTopLeft(find.byKey(Key('member-$id'))).dy;
    expect(y('s1'), lessThan(y('s2')));
  });

  testWidgets('approve one who asked; remove a member after asking', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, '/classes/details/c1');
    await tester.tap(find.byKey(const Key('approve-s3')));
    await tester.pumpAndSettle();
    expect(api.to('POST /classes/c1/students/s3/approve'), hasLength(1));
    expect(api.to('GET /classes/c1'), hasLength(2));

    await tester.scrollUntilVisible(
      find.byKey(const Key('remove-s1')),
      200,
      scrollable: _scrollable(),
    );
    await tester.tap(find.byKey(const Key('remove-s1')));
    await tester.pumpAndSettle();
    expect(
      find.text(_en.classesRosterRemoveTitle('Karim Hasan')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('remove-confirm')));
    await tester.pumpAndSettle();
    expect(api.to('DELETE /classes/c1/students').single.body, {
      'student_ids': ['s1'],
    });
  });

  testWidgets('add students; view one; filter by section', (tester) async {
    final api = _api();
    await _open(tester, api, '/classes/details/c1');
    await tester.tap(find.byKey(const Key('add-students')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('invite-input')),
      '01000000001',
    );
    await tester.tap(find.byKey(const Key('invite-add')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('invite-send')));
    await tester.pumpAndSettle();
    expect(api.to('POST /classes/c1/students').single.body, {
      'students': ['01000000001'],
    });

    await tester.scrollUntilVisible(
      find.byKey(const Key('view-s1')),
      200,
      scrollable: _scrollable(),
    );
    await tester.tap(find.byKey(const Key('view-s1')));
    await tester.pumpAndSettle();
    expect(find.text('123456'), findsOneWidget);
    await tester.tap(find.text(_en.classesFormClose));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('roster-section')),
      -200,
      scrollable: _scrollable(),
    );
    await tester.tap(find.byKey(const Key('roster-section')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('member-s1')), findsNothing);
    expect(find.byKey(const Key('member-s2')), findsOneWidget);
  });

  testWidgets('discussions: a teacher starts a private chat with a joined '
      'student', (tester) async {
    const scope = '/classes/c1/subjects/sub1';
    final api = _api()
      ..on(
        'GET /classes/c1/discussion-subjects',
        (_) => ok([
          {
            'id': 'sub1',
            'class_subject': {
              'id': 'sub1',
              'subject': {'id': 'm', 'name': 'Mathematics', 'code': 'MAT'},
            },
            'teachers': [
              {'id': 'user-1', 'name': 'Rina Akter'},
            ],
          },
        ]),
      )
      ..on(
        'GET $scope/discussions',
        (_) => ok({
          'items': <Object>[],
          'meta': {'page': 1, 'total_pages': 1},
        }),
      )
      ..on('GET $scope/private-conversations', (_) => ok(<Object>[]))
      ..on(
        'POST $scope/private-conversations',
        (_) => ok({
          'id': 'v1',
          'student': {'id': 's1', 'name': 'Karim Hasan'},
          'teacher': {'id': 'user-1', 'name': 'Rina Akter'},
        }),
      )
      ..on(
        'GET $scope/private-conversations/v1/messages',
        (_) => ok({
          'items': <Object>[],
          'meta': {'page': 1, 'total_pages': 1},
        }),
      );
    await _open(tester, api, '/classes/details/c1');
    await tester.tap(find.text(_en.classesTabsDiscussions));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(_en.discussionsPrivate),
      200,
      scrollable: _scrollable(),
    );
    await tester.tap(find.text(_en.discussionsPrivate));
    await tester.pumpAndSettle();
    // Only joined students (not the invited or the one who asked).
    expect(find.text(_en.discussionsChatStartWithStudent), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('chat-start')),
      200,
      scrollable: _scrollable(),
    );
    await tester.tap(find.byKey(const Key('chat-start')));
    await tester.pumpAndSettle();
    expect(api.to('POST $scope/private-conversations').single.body, {
      'student_id': 's1',
    });
    // The other person is the student.
    expect(find.text('Karim Hasan'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 21));
  });

  testWidgets('a class that is not theirs: not found', (tester) async {
    await _open(tester, _api(one: (_) => apiError(404)), '/classes/details/c1');
    expect(find.textContaining('not found'), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), '/classes/details/c1', lang: 'bn');
    expect(find.text(bn.classesAddStudents), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

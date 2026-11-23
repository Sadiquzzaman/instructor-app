import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/auth/screens/login_screen.dart';
import 'package:instructor_app/features/join/data/join_links.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();
const _class = '2f1c3ab1-3899-4f11-8cf3-7bf1a7e51f7b';
const _test = 'd1fc1153-0b4a-409a-bcd4-18eec241f306';

Session _as(String role) =>
    Session.fromPayload({...sessionPayload(), 'role': role});

FakeApi _api({String joinStatus = 'PENDING'}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /calendar/me', (_) => ok({'items': <Object>[]}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on('GET /student/classes', (_) => ok(<Object>[]))
  ..on(
    'GET /classes/$_class',
    (_) => ok({
      'id': _class,
      'class_name': 'Class 6',
      'description': null,
      'created_user_name': 'Demo Owner',
    }),
  )
  ..on(
    'POST /classes/$_class/join',
    (_) => ok({'class_id': _class, 'status': joinStatus}),
  )
  ..on(
    'GET /exams/$_test',
    (_) => ok({
      'id': _test,
      'test_name': 'Weekly quiz',
      'duration_minutes': 30,
      'test_audience': 'selected_class',
      'created_user_name': 'Rina Akter',
    }),
  );

String _location(ProviderContainer app) => app
    .read(routerProvider)
    .routerDelegate
    .currentConfiguration
    .last
    .matchedLocation;

void main() {
  test('reads the web share links, and nothing else', () {
    expect(parseJoinLink('https://instructor.academy/join/class/$_class'), (
      kind: 'class',
      id: _class,
    ));
    expect(
      parseJoinLink(' https://beta.instructor.academy/join/test/$_test/ '),
      (kind: 'test', id: _test),
    );
    expect(parseJoinLink('/join/class/$_class'), (kind: 'class', id: _class));
    expect(parseJoinLink('https://instructor.academy/join/class/12'), isNull);
    expect(parseJoinLink('https://instructor.academy/classes/$_class'), isNull);
    expect(parseJoinLink('ftp://x/join/class/$_class'), isNull);
    expect(parseJoinLink('hello'), isNull);
    expect(joinRoute((kind: 'test', id: _test)), '/join/test/$_test');
  });

  testWidgets('a student joins a class from its link; it waits for approval', (
    tester,
  ) async {
    final api = _api();
    final app = await pumpInstructorApp(
      tester,
      api: api,
      session: _as('STUDENT'),
    );
    app.read(routerProvider).go('/join/class/$_class');
    await tester.pumpAndSettle();
    expect(find.text(_en.classesJoinTitle('Class 6', 'Demo Owner')), findsOne);
    expect(find.text(_en.classesJoinNoDescription), findsOneWidget);
    // The summary is the public one, read without the token.
    expect(
      api.to('GET /classes/$_class').single.headers['Authorization'],
      isNull,
    );
    await tester.tap(find.byKey(const Key('join-class')));
    await tester.pumpAndSettle();
    expect(api.to('POST /classes/$_class/join'), hasLength(1));
    expect(find.byKey(const Key('join-result')), findsOneWidget);
    expect(find.textContaining('Class: Class 6'), findsOneWidget);
    await tester.tap(find.byKey(const Key('join-done')));
    await tester.pumpAndSettle();
    expect(_location(app), AppRoutes.classes);
  });

  testWidgets('already in the class: says so and opens it', (tester) async {
    final api = _api()
      ..on(
        'GET /student/classes',
        (_) => ok([
          {
            'class': {'id': _class, 'class_name': 'Class 6'},
            'id': _class,
            'class_name': 'Class 6',
          },
        ]),
      );
    final app = await pumpInstructorApp(
      tester,
      api: api,
      session: _as('STUDENT'),
    );
    app.read(routerProvider).go('/join/class/$_class');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('join-already')), findsOneWidget);
    expect(find.byKey(const Key('join-class')), findsNothing);
    await tester.tap(find.byKey(const Key('join-open-class')));
    await tester.pump();
    expect(_location(app), '${AppRoutes.classes}/details/$_class');
    expect(api.to('POST /classes/$_class/join'), isEmpty);
    await tester.pumpAndSettle();
  });

  testWidgets('teachers see the class but cannot join it', (tester) async {
    final app = await pumpInstructorApp(
      tester,
      api: _api(),
      session: _as('TEACHER'),
    );
    app.read(routerProvider).go('/join/class/$_class');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('join-class')), findsNothing);
    expect(find.text(_en.appJoinStudentsOnly), findsOneWidget);
  });

  testWidgets('a test link: who made it, how long; Start opens the test', (
    tester,
  ) async {
    final app = await pumpInstructorApp(
      tester,
      api: _api(),
      session: _as('STUDENT'),
    );
    app.read(routerProvider).go('/join/test/$_test');
    await tester.pumpAndSettle();
    expect(
      find.text(_en.testsJoinTitle('Weekly quiz', 'Rina Akter')),
      findsOne,
    );
    expect(find.text(_en.testsJoinDuration(30)), findsOneWidget);
    expect(find.text(_en.testsJoinPrivate), findsOneWidget);
    await tester.tap(find.byKey(const Key('join-test')));
    await tester.pump();
    expect(_location(app), '/tests/$_test/take');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('a link opened signed out waits for sign-in', (tester) async {
    final app = await pumpInstructorApp(tester, api: _api());
    app.read(routerProvider).go('/join/class/$_class');
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    await app.read(sessionHolderProvider).save(_as('STUDENT'));
    await tester.pumpAndSettle();
    expect(_location(app), '/join/class/$_class');
  });

  testWidgets('Join with a link: a wrong link says so; a right one opens', (
    tester,
  ) async {
    final app = await pumpInstructorApp(
      tester,
      api: _api(),
      session: _as('STUDENT'),
    );
    app.read(routerProvider).go(AppRoutes.classes);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('classes-join-link')));
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byKey(const Key('join-link-field')),
      matching: find.byType(TextField),
    );
    // Ready to paste: the field has the focus.
    expect(tester.widget<TextField>(field).autofocus, isTrue);
    await tester.enterText(field, 'https://example.com/whatever');
    await tester.tap(find.byKey(const Key('join-link-open')));
    await tester.pumpAndSettle();
    expect(find.text(_en.appJoinLinkInvalid), findsOneWidget);
    await tester.enterText(
      field,
      'https://beta.instructor.academy/join/class/$_class',
    );
    await tester.tap(find.byKey(const Key('join-link-open')));
    await tester.pumpAndSettle();
    expect(_location(app), '/join/class/$_class');
  });

  test('Android opens the share links in the app', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:pathPrefix="/join/class/"'));
    expect(manifest, contains('android:pathPrefix="/join/test/"'));
    expect(manifest, contains('android:host="instructor.academy"'));
    expect(manifest, contains('android:autoVerify="true"'));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
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
    'GET /organizations/org-1/subjects',
    (_) => ok([
      {
        'id': 's1',
        'name': 'Mathematics',
        'code': 'MATH',
        'classes': [
          {'class_name': 'Class 6'},
          {'class_name': 'Class 7'},
        ],
      },
    ]),
  )
  ..on('POST /organizations/org-1/subjects', (_) => ok({'id': 's2'}))
  ..on('PATCH /organizations/org-1/subjects/s1', (_) => ok({'id': 's1'}))
  ..on('DELETE /organizations/org-1/subjects/s1', (_) => ok(null))
  ..on(
    'GET /classes',
    (_) => ok([
      {
        'id': 'c6',
        'class_name': 'Class 6',
        'classSubjects': [
          {
            'subject': {'name': 'Mathematics', 'code': 'MATH'},
          },
          {
            'subject': {'name': 'English', 'code': null},
          },
        ],
        'classStudents': [
          {'id': 'x'},
          {'id': 'y'},
        ],
      },
    ]),
  );

Future<void> _open(
  WidgetTester tester,
  FakeApi api,
  String route, {
  String role = 'OWNER',
  String? lang,
}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _member(role),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go(route);
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('subjects: code and classes', (tester) async {
    await _open(tester, _api(), '/organization/subjects');
    expect(find.text('Mathematics'), findsOneWidget);
    expect(find.textContaining('MATH'), findsOneWidget);
    expect(find.textContaining('Class 6, Class 7'), findsOneWidget);
    // The level word, not the token.
    expect(find.textContaining('[['), findsNothing);
  });

  testWidgets('add a subject: name and code are needed', (tester) async {
    final api = _api();
    await _open(tester, api, '/organization/subjects');
    await tester.tap(find.byKey(const Key('subject-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('subject-name')), 'Physics');
    await tester.tap(find.byKey(const Key('subject-save')));
    await tester.pumpAndSettle();
    expect(find.text(_en.organizationSubjectsRequired), findsOneWidget);
    expect(api.to('POST /organizations/org-1/subjects'), isEmpty);
    await tester.enterText(find.byKey(const Key('subject-code')), ' PHY ');
    await tester.tap(find.byKey(const Key('subject-save')));
    await tester.pumpAndSettle();
    expect(api.to('POST /organizations/org-1/subjects').single.body, {
      'name': 'Physics',
      'code': 'PHY',
    });
    expect(api.to('GET /organizations/org-1/subjects').length, greaterThan(1));
  });

  testWidgets('rename; delete asks first', (tester) async {
    final api = _api();
    await _open(tester, api, '/organization/subjects');
    await tester.tap(find.byKey(const Key('subject-edit-s1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('subject-name')), 'Maths');
    await tester.tap(find.byKey(const Key('subject-save')));
    await tester.pumpAndSettle();
    expect(api.to('PATCH /organizations/org-1/subjects/s1').single.body, {
      'name': 'Maths',
      'code': 'MATH',
    });

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('subject-delete-s1')));
    await tester.pumpAndSettle();
    expect(
      find.text(_en.organizationSubjectsDeleteTitle('Mathematics')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('subject-delete-confirm')));
    await tester.pumpAndSettle();
    expect(api.to('DELETE /organizations/org-1/subjects/s1'), hasLength(1));
  });

  testWidgets('subjects: not for teachers', (tester) async {
    await _open(tester, _api(), '/organization/subjects', role: 'TEACHER');
    expect(find.text(_en.organizationGateNoAccessTitle), findsOneWidget);
  });

  testWidgets('classes: subjects with codes, student count; one opens', (
    tester,
  ) async {
    await _open(tester, _api(), '/organization/classes', role: 'TEACHER');
    expect(find.text('Class 6'), findsOneWidget);
    expect(find.textContaining('Mathematics (MATH), English'), findsOneWidget);
    expect(find.textContaining(': 2'), findsOneWidget);
    expect(find.byKey(const Key('class-view-c6')), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), '/organization/subjects', lang: 'bn');
    expect(find.text(bn.organizationSubjectsTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

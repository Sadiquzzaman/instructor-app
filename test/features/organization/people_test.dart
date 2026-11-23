import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/organization/screens/people_screen.dart';
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

Map<String, Object?> _m(
  String id,
  String role,
  String name, {
  String? phone,
  String? tid,
  String? sid,
}) => {
  'id': id,
  'role': role,
  'created_at': '2026-09-01T00:00:00Z',
  'branch_id': null,
  'user': {
    'full_name': name,
    'email': null,
    'phone': phone,
    'teacher_public_id': tid,
    'student_public_id': sid,
    'public_id': null,
  },
};

Map<String, Object?> _lookup({
  bool found = true,
  bool verified = true,
  Map<String, Object?>? membership,
}) => found
    ? {
        'found': true,
        'query': '01111000000',
        'query_type': 'phone',
        'user': {
          'id': 'u9',
          'full_name': 'Jamal Uddin',
          'email': null,
          'phone': '01111000000',
          'teacher_public_id': 'T-77',
          'student_public_id': null,
          'is_otp_verified': verified,
        },
        'membership': membership,
      }
    : {
        'found': false,
        'query': '01111000000',
        'query_type': 'phone',
        'message': 'No account uses this number yet.',
      };

FakeApi _api({Map<String, Object?>? lookup}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /organizations/org-1/members',
    (_) => ok([
      _m('m0', 'OWNER', 'Owner Person', tid: 'T-1'),
      _m('m1', 'TEACHER', 'Rina Akter', phone: '01100000001', tid: 'T-12'),
      _m('m2', 'ADMIN', 'Admin Person', tid: 'T-13'),
      _m('m3', 'ASSISTANT', 'Help Desk'),
      _m('m4', 'STUDENT', 'Karim Hasan', sid: 'S-9'),
    ]),
  )
  ..on(
    'GET /organizations/org-1/members/lookup',
    (_) => ok(lookup ?? _lookup()),
  )
  ..on(
    'POST /organizations/org-1/members',
    (_) => ok({'status': 'added', 'member': _m('m9', 'TEACHER', 'Jamal')}),
  )
  ..on('DELETE /organizations/org-1/members/m1', (_) => ok(null))
  ..on('PATCH /organizations/org-1/members/m1', (_) => ok(null))
  ..on(
    'POST /organizations/org-1/members/import',
    (_) => ok({
      'total': 3,
      'imported': 2,
      'already_member': 1,
      'invitation_sent': 0,
      'user_not_found': 0,
      'invalid': 0,
      'duplicate': 0,
      'results': <Object>[],
    }),
  )
  ..on(
    'GET /attendance/branches',
    (_) => ok([
      {'id': 'b1', 'name': null, 'is_default': true},
      {'id': 'b2', 'name': 'Uttara', 'is_default': false},
    ]),
  )
  ..on(
    'GET /sections',
    (_) => ok([
      {'id': 'sec10', 'name': 'A', 'class_id': 'c10'},
      {'id': 'sec2', 'name': 'A', 'class_id': 'c2'},
    ]),
  )
  ..on(
    'GET /classes',
    (_) => ok([
      {'id': 'c10', 'class_name': 'Class 10'},
      {'id': 'c2', 'class_name': 'Class 2'},
    ]),
  )
  ..on('POST /sections/sec2/enrolments', (_) => ok({'outcome': 'ENROLLED'}));

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

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('teachers: staff only, searchable; no actions on the owner', (
    tester,
  ) async {
    await _open(tester, _api(), '/organization/teachers');
    expect(find.text(_en.organizationMembersTeachers), findsOneWidget);
    expect(find.text('Rina Akter'), findsOneWidget);
    expect(find.text('Admin Person'), findsOneWidget);
    expect(find.text('Karim Hasan'), findsNothing);
    expect(find.text('Help Desk'), findsNothing);
    expect(find.byKey(const Key('remove-m0')), findsNothing);
    expect(find.byKey(const Key('role-m1')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('people-search')), 'rina');
    await tester.pumpAndSettle();
    expect(find.text('Admin Person'), findsNothing);
    expect(find.text('Rina Akter'), findsOneWidget);
  });

  testWidgets('students and assistants show their own people', (tester) async {
    await _open(tester, _api(), '/organization/students');
    expect(find.text('Karim Hasan'), findsOneWidget);
    expect(find.textContaining('S-9'), findsOneWidget);
    expect(find.text('Rina Akter'), findsNothing);
  });

  testWidgets('assistants read; they do not add or remove', (tester) async {
    await _open(tester, _api(), '/organization/teachers', role: 'ASSISTANT');
    expect(find.text('Rina Akter'), findsOneWidget);
    expect(find.byKey(const Key('people-add')), findsNothing);
    expect(find.byKey(const Key('remove-m1')), findsNothing);
  });

  testWidgets('assistants page: owners and admins only', (tester) async {
    await _open(tester, _api(), '/organization/assistants', role: 'ASSISTANT');
    expect(find.text(_en.organizationGateNoAccessTitle), findsOneWidget);
  });

  testWidgets('remove asks first', (tester) async {
    final api = _api();
    await _open(tester, api, '/organization/teachers');
    await _tap(tester, find.byKey(const Key('remove-m1')));
    expect(
      find.text(_en.organizationMembersRemoveTitle('Rina Akter')),
      findsOneWidget,
    );
    await tester.tap(find.text(_en.uiCancel));
    await tester.pumpAndSettle();
    expect(api.to('DELETE /organizations/org-1/members/m1'), isEmpty);
    await _tap(tester, find.byKey(const Key('remove-m1')));
    await tester.tap(find.byKey(const Key('remove-confirm')));
    await tester.pumpAndSettle();
    expect(api.to('DELETE /organizations/org-1/members/m1'), hasLength(1));
    expect(api.to('GET /organizations/org-1/members').length, greaterThan(1));
  });

  testWidgets('a branch manager needs a branch', (tester) async {
    final api = _api();
    await _open(tester, api, '/organization/teachers');
    await _tap(tester, find.byKey(const Key('role-m1')));
    await tester.tap(find.byKey(const Key('role-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.organizationRolesBRANCHMANAGER).last);
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('role-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(find.byKey(const Key('branch-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uttara').last);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(api.to('PATCH /organizations/org-1/members/m1').single.body, {
      'role': 'BRANCH_MANAGER',
      'branch_id': 'b2',
    });
  });

  testWidgets('add a teacher found by phone', (tester) async {
    final api = _api();
    await _open(tester, api, '/organization/teachers');
    await tester.tap(find.byKey(const Key('people-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lookup-find')));
    await tester.pumpAndSettle();
    expect(find.text(_en.organizationMembersMissingQuery), findsOneWidget);
    expect(api.to('GET /organizations/org-1/members/lookup'), isEmpty);

    await tester.enterText(
      find.byKey(const Key('lookup-query')),
      ' 01111000000 ',
    );
    await tester.tap(find.byKey(const Key('lookup-find')));
    await tester.pumpAndSettle();
    expect(
      api.to('GET /organizations/org-1/members/lookup').single.query['q'],
      '01111000000',
    );
    expect(find.text('Jamal Uddin'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('lookup-add')));
    expect(api.to('POST /organizations/org-1/members').single.body, {
      'query': '01111000000',
      'role': 'TEACHER',
    });
    expect(find.byType(AddPeopleScreen), findsNothing);
  });

  testWidgets('not found: invite; unverified: cannot add', (tester) async {
    await _open(
      tester,
      _api(lookup: _lookup(verified: false)),
      '/organization/teachers',
    );
    await tester.tap(find.byKey(const Key('people-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('lookup-query')), '017');
    await tester.tap(find.byKey(const Key('lookup-find')));
    await tester.pumpAndSettle();
    expect(find.text(_en.organizationMembersNotVerified), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('lookup-add')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a student straight into a section (natural order)', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, '/organization/students');
    await tester.tap(find.byKey(const Key('people-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-section')));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Class 2 A').last).dy,
      lessThan(tester.getTopLeft(find.text('Class 10 A').last).dy),
    );
    await tester.tap(find.text('Class 2 A').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('lookup-query')),
      '01111000000',
    );
    await tester.tap(find.byKey(const Key('lookup-find')));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('lookup-add')));
    expect(api.to('POST /sections/sec2/enrolments').single.body, {
      'student_id': 'u9',
    });
  });

  testWidgets('a list of phone numbers', (tester) async {
    final api = _api();
    await _open(tester, api, '/organization/teachers');
    await tester.tap(find.byKey(const Key('people-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('phone-list')),
      '01100000001\n01100000002, 01100000003',
    );
    await _tap(tester, find.byKey(const Key('phone-list-add')));
    expect(api.to('POST /organizations/org-1/members/import').single.body, {
      'identifiers': ['01100000001', '01100000002', '01100000003'],
      'role': 'TEACHER',
      'invite_missing': false,
    });
    expect(find.byKey(const Key('phone-summary')), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), '/organization/teachers', lang: 'bn');
    expect(find.text(bn.organizationMembersTeachers), findsWidgets);
    await tester.tap(find.byKey(const Key('people-add')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

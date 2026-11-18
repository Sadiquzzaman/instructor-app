import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/organization/screens/assignments_screen.dart';
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

FakeApi _api({bool closed = false}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /classes',
    (_) => ok([
      {
        'id': 'c6',
        'class_name': 'Class 6',
        'classSubjects': [
          {
            'id': 'cs1',
            'subject_id': 'math',
            'subject': {'id': 'math', 'name': 'Mathematics', 'code': 'M'},
          },
        ],
      },
    ]),
  )
  ..on(
    'GET /organizations/org-1/subjects',
    (_) => ok([
      {'id': 'math', 'name': 'Mathematics', 'code': 'M'},
      {'id': 'eng', 'name': 'English', 'code': null},
    ]),
  )
  ..on(
    'GET /organizations/org-1/assignable-teachers',
    (_) => ok([
      {
        'user': {'id': 't1', 'full_name': 'Rina Akter'},
      },
      {
        'user': {'id': 't2', 'full_name': 'Jamal Uddin'},
      },
    ]),
  )
  ..on(
    'GET /sessions',
    (_) => ok([
      {
        'id': 'se1',
        'name': '2026',
        'is_default': true,
        'status': closed ? 'CLOSED' : 'OPEN',
      },
    ]),
  )
  ..on(
    'GET /sections',
    (_) => ok([
      {'id': 'sa', 'name': 'A', 'class_id': 'c6'},
      {'id': 'sb', 'name': 'B', 'class_id': 'c6'},
    ]),
  )
  ..on(
    'GET /offerings',
    (_) => ok([
      {
        'id': 'oa',
        'section_id': 'sa',
        'subject': {'id': 'math', 'name': 'Mathematics', 'code': 'M'},
        'teachers': [
          {'id': 't1', 'full_name': 'Rina Akter'},
        ],
      },
      {
        'id': 'ob',
        'section_id': 'sb',
        'subject': {'id': 'math', 'name': 'Mathematics', 'code': 'M'},
        'teachers': <Object>[],
      },
    ]),
  )
  ..on('PUT /offerings/oa/teachers', (_) => ok(null))
  ..on('PUT /offerings/ob/teachers', (_) => ok(null))
  ..on('POST /classes/c6/subjects', (_) => ok(null))
  ..on('DELETE /classes/c6/subjects/cs1', (_) => ok(null));

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
  app.read(routerProvider).go('/organization/assignments');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

Finder _scrollable() => find
    .descendant(
      of: find.byType(AssignmentsScreen),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _show(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: _scrollable());
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String key, String option) async {
  await _show(tester, find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await _show(tester, f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every subject class with its teacher, or none', (tester) async {
    await _open(tester, _api());
    await _show(tester, find.byKey(const Key('row-oa-t1')));
    expect(find.text('Class 6 A · Mathematics — M'), findsOneWidget);
    expect(find.text('Rina Akter'), findsWidgets);
    await _show(tester, find.byKey(const Key('row-unassigned-ob')));
    expect(find.text(_en.organizationAssignmentsUnassigned), findsWidgets);
  });

  testWidgets('a teacher for a subject in every section at once', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    await _pick(tester, 'assign-class', 'Class 6');
    await _pick(tester, 'assign-section-c6-null', 'All sections of the class');
    await _pick(tester, 'assign-subject-all-null', 'Mathematics — M');
    await _pick(tester, 'assign-teacher-math-null', 'Jamal Uddin');
    await _tap(tester, find.byKey(const Key('assign-save')));
    // Each subject class keeps its teachers and gets Jamal.
    expect(api.to('PUT /offerings/oa/teachers').single.body, {
      'teacher_ids': ['t1', 't2'],
    });
    expect(api.to('PUT /offerings/ob/teachers').single.body, {
      'teacher_ids': ['t2'],
    });
  });

  testWidgets('change a teacher replaces them in that subject class', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    await _tap(tester, find.byKey(const Key('edit-oa-t1')));
    await _pick(tester, 'assign-teacher-math-oa-t1', 'Jamal Uddin');
    await _tap(tester, find.byKey(const Key('assign-save')));
    expect(api.to('PUT /offerings/oa/teachers').single.body, {
      'teacher_ids': ['t2'],
    });
    expect(api.to('PUT /offerings/ob/teachers'), isEmpty);
  });

  testWidgets('remove a teacher asks first; fill an empty one', (tester) async {
    final api = _api();
    await _open(tester, api);
    await _tap(tester, find.byKey(const Key('unassign-oa-t1')));
    expect(
      find.text(
        _en.organizationAssignmentsUnassignTitle(
          'Rina Akter',
          'Mathematics — M',
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('assignments-confirm')));
    await tester.pumpAndSettle();
    expect(api.to('PUT /offerings/oa/teachers').single.body, {
      'teacher_ids': <String>[],
    });

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _pick(tester, 'quick-ob', 'Rina Akter');
    expect(api.to('PUT /offerings/ob/teachers').single.body, {
      'teacher_ids': ['t1'],
    });
  });

  testWidgets('step 1: add a subject to a class, remove one', (tester) async {
    final api = _api();
    await _open(tester, api);
    await _pick(tester, 'assign-class', 'Class 6');
    await _pick(tester, 'assign-attach', 'English');
    await _tap(tester, find.byKey(const Key('assign-attach-add')));
    expect(api.to('POST /classes/c6/subjects').single.body, {
      'subject_id': 'eng',
    });

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('subject-remove-cs1')));
    await tester.tap(find.byKey(const Key('assignments-confirm')));
    await tester.pumpAndSettle();
    expect(api.to('DELETE /classes/c6/subjects/cs1'), hasLength(1));
  });

  testWidgets('a closed session is read-only', (tester) async {
    await _open(tester, _api(closed: true));
    expect(find.byKey(const Key('assign-closed')), findsOneWidget);
    expect(find.byKey(const Key('assign-save')), findsNothing);
    await _show(tester, find.byKey(const Key('row-oa-t1')));
    expect(find.byKey(const Key('edit-oa-t1')), findsNothing);
  });

  testWidgets('not for teachers', (tester) async {
    await _open(tester, _api(), role: 'TEACHER');
    expect(find.text(_en.organizationGateNoAccessTitle), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.organizationAssignmentsTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/ielts/data/courses.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';
import 'ielts_overview_test.dart' show ieltsMember;

final _en = AppLocalizationsEn();

Map<String, Object?> _course({
  String id = 'c1',
  int students = 12,
  String status = 'RUNNING',
}) => {
  'id': id,
  'title': 'Band 7 Academic — evening',
  'branch': {'id': 'b0', 'name': null, 'is_default': true},
  'start_date': '2026-11-01',
  'end_date': '2027-01-31',
  'status': status,
  'modules': ['LISTENING', 'READING', 'WRITING', 'SPEAKING'],
  'seat_limit': 20,
  'students': students,
  'teachers': [
    {
      'module': 'WRITING',
      'offering_id': 'o1',
      'teachers': [
        {'id': 't1', 'full_name': 'Nadia Rahman'},
      ],
    },
    {'module': 'SPEAKING', 'offering_id': 'o2', 'teachers': <Object>[]},
  ],
  'class_id': 'k1',
};

FakeApi _api() => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on(
    'GET /me/entitlements',
    (_) => ok({
      'features': {'ielts': true},
    }),
  )
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /ielts/courses',
    (_) => ok([_course(), _course(id: 'c2', students: 0, status: 'UPCOMING')]),
  )
  ..on(
    'GET /attendance/branches',
    (_) => ok([
      {'id': 'b0', 'name': 'Main', 'is_default': true},
    ]),
  )
  ..on(
    'GET /organizations/org-1/assignable-teachers',
    (_) => ok([
      {
        'user': {'id': 't1', 'full_name': 'Nadia Rahman'},
      },
    ]),
  )
  ..on('POST /ielts/courses', (_) => ok({'id': 'c3'}))
  ..on('PATCH /ielts/courses/c1', (_) => ok({'id': 'c1'}))
  ..on('DELETE /ielts/courses/c2', (_) => ok(null));

Future<void> _open(
  WidgetTester tester,
  FakeApi api,
  String role,
  String route, {
  String? lang,
}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: ieltsMember(role),
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
  test('the body: modules in test order, seats, teachers per module', () {
    expect(
      courseBody(
        title: ' Evening ',
        startDate: '2027-01-05',
        endDate: '2027-03-31',
        modules: ['WRITING', 'LISTENING'],
        seatLimit: '20',
        teachers: {'WRITING': 't1', 'LISTENING': ''},
      ),
      {
        'title': 'Evening',
        'start_date': '2027-01-05',
        'end_date': '2027-03-31',
        'modules': ['LISTENING', 'WRITING'],
        'seat_limit': 20,
        'teachers': {
          'LISTENING': <String>[],
          'WRITING': ['t1'],
        },
      },
    );
    // No seat limit, no teachers list: neither is sent as a change.
    final b = courseBody(
      title: 'x',
      startDate: 'a',
      endDate: 'b',
      modules: ['READING'],
    );
    expect(b['seat_limit'], isNull);
    expect(b.containsKey('teachers'), isFalse);
  });

  testWidgets('an owner: courses, filter, make one', (tester) async {
    final api = _api();
    await _open(tester, api, 'OWNER', '/ielts/courses');
    expect(
      find.textContaining(_en.ieltsCoursesSeatsTaken(12, 20)),
      findsOneWidget,
    );
    expect(find.textContaining('Nadia Rahman'), findsWidgets);
    // Only a course without students can be removed.
    expect(find.byKey(const Key('course-remove-c1')), findsNothing);
    expect(find.byKey(const Key('course-remove-c2')), findsOneWidget);

    await _tap(tester, find.byKey(const Key('course-filter-UPCOMING')));
    expect(find.byKey(const Key('course-c1')), findsNothing);
    expect(find.byKey(const Key('course-c2')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('course-filter-all')));

    await _tap(tester, find.byKey(const Key('course-new')));
    final save = find.byKey(const Key('course-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('course-title')), 'Morning');
    await tester.pump();
    await _tap(tester, find.byKey(const Key('course-module-WRITING')));
    expect(find.byKey(const Key('course-teacher-WRITING')), findsOneWidget);
    // Dates are still missing.
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
  });

  testWidgets('remove an empty course after asking', (tester) async {
    final api = _api();
    await _open(tester, api, 'ADMIN', '/ielts/courses');
    await _tap(tester, find.byKey(const Key('course-remove-c2')));
    expect(find.text(_en.ieltsCoursesRemoveDetail), findsOneWidget);
    await _tap(tester, find.byKey(const Key('course-remove-confirm')));
    expect(api.to('DELETE /ielts/courses/c2'), hasLength(1));
  });

  testWidgets('change a course: the form starts from it', (tester) async {
    final api = _api();
    await _open(tester, api, 'OWNER', '/ielts/courses');
    await _tap(tester, find.byKey(const Key('course-edit-c1')));
    await tester.enterText(find.byKey(const Key('course-title')), 'Renamed');
    await tester.pump();
    await _tap(tester, find.byKey(const Key('course-save')));
    final body = api.to('PATCH /ielts/courses/c1').single.body! as Map;
    expect(body['title'], 'Renamed');
    expect(body['start_date'], '2026-11-01');
    expect(body['modules'], ['LISTENING', 'READING', 'WRITING', 'SPEAKING']);
    expect(body['seat_limit'], 20);
    expect((body['teachers'] as Map)['WRITING'], ['t1']);
    expect((body['teachers'] as Map)['SPEAKING'], <String>[]);
  });

  testWidgets('a teacher reads the courses they teach', (tester) async {
    await _open(tester, _api(), 'TEACHER', '/ielts/courses');
    expect(find.byKey(const Key('course-new')), findsNothing);
    expect(find.byKey(const Key('course-edit-c1')), findsNothing);
    expect(find.byKey(const Key('course-class-c1')), findsOneWidget);
  });

  testWidgets('a student: my courses with their teachers', (tester) async {
    await _open(tester, _api(), 'STUDENT', '/ielts/my-courses');
    expect(find.text(_en.ieltsCoursesMyTitle), findsWidgets);
    expect(find.byKey(const Key('my-course-c1')), findsOneWidget);
    expect(find.textContaining(_en.ieltsCoursesNoTeacher), findsWidgets);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), 'OWNER', '/ielts/courses', lang: 'bn');
    expect(find.text(bn.ieltsCoursesTitle), findsWidgets);
    expect(tester.takeException(), isNull);
    await _tap(tester, find.byKey(const Key('course-new')));
    expect(tester.takeException(), isNull);
  });
}

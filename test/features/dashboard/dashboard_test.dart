import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/features/dashboard/screens/teacher_dashboard_screen.dart';
import 'package:instructor_app/features/today/screens/today_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Session _teacher() => Session.fromPayload({
  ...sessionPayload(),
  'role': 'TEACHER',
  'full_name': 'Rina Akter',
});

Map<String, Object?> _student(String id, String name, num? avg) => {
  'student_id': id,
  'name': name,
  'tests_taken': 2,
  'avg_score_percent': avg,
};

Map<String, Object?> _full() => {
  'pending_grading_count': 3,
  'live_tests': [
    {
      'id': 'e1',
      'test_name': 'Algebra quiz',
      'class_name': 'Class 6 A',
      'participant_count': 30,
      'submitted_count': 12,
      'remaining_seconds': 125,
      'exam_end_time': '2026-11-18T05:00:00.000Z',
    },
    {
      'id': 'e2',
      'test_name': 'Geometry quiz',
      'class_name': 'Class 7 B',
      'participant_count': 25,
      'submitted_count': 0,
      'remaining_seconds': 600,
      'exam_end_time': '2026-11-18T06:00:00.000Z',
    },
  ],
  'students_summary': {'total': 55, 'joined': 50, 'pending': 5, 'active': 48},
  'upcoming_tests': [
    {
      'id': 'u2',
      'test_name': 'Later test',
      'class_name': 'Class 7 B',
      'exam_start_time': '2026-11-25T04:00:00.000Z',
      'duration_minutes': 90,
      'student_count': 25,
    },
    {
      'id': 'u1',
      'test_name': 'Fractions',
      'class_name': 'Class 6 A',
      'exam_start_time': '2026-11-20T04:00:00.000Z',
      'duration_minutes': 45,
      'student_count': 30,
    },
  ],
  'classes_summary': [
    {'id': 'c1', 'name': 'Class 6 A', 'student_count': 30},
    {'id': 'c2', 'name': 'Class 7 B', 'student_count': 25},
  ],
  'top_students_by_class': [
    {
      'class_id': 'c1',
      'class_name': 'Class 6 A',
      'students': [
        _student('s1', 'Karim Hasan', 72.5),
        _student('s2', 'Nadia Islam', 91),
        _student('s3', 'Sami Rahman', null),
        for (var i = 4; i <= 12; i++) _student('s$i', 'Student $i', 50 - i),
      ],
    },
    {
      'class_id': 'c2',
      'class_name': 'Class 7 B',
      'students': [_student('s20', 'Tania Akter', 88)],
    },
  ],
  'calendar_events': <Object>[],
  'activity': {'period': 'monthly', 'data': <Object>[]},
};

Map<String, Object?> _empty() => {
  'pending_grading_count': 0,
  'live_tests': <Object>[],
  'students_summary': {'total': 0, 'joined': 0, 'pending': 0, 'active': 0},
  'upcoming_tests': <Object>[],
  'classes_summary': <Object>[],
  'top_students_by_class': <Object>[],
  'calendar_events': <Object>[],
  'activity': {'period': 'monthly', 'data': <Object>[]},
};

FakeApi _api(FakeHandler dashboard) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /calendar/me', (_) => ok({'items': <Object>[]}))
  ..on('GET /dashboard/teacher', dashboard);

Finder _scrollable() => find
    .descendant(
      of: find.byType(TeacherDashboardScreen),
      matching: find.byType(Scrollable),
    )
    .first;

/// Scrolls [f] into the middle of the screen, clear of the app bar.
Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: _scrollable());
  await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a teacher starts on the dashboard: what needs doing now', (
    tester,
  ) async {
    final api = _api((_) => ok(_full()));
    await pumpInstructorApp(tester, api: api, session: _teacher());

    expect(find.byType(TeacherDashboardScreen), findsOneWidget);
    expect(find.text(_en.dashboardWelcome('Rina Akter')), findsOneWidget);
    expect(api.to('GET /dashboard/teacher'), hasLength(1));

    // To mark: highlighted, with the way to marking.
    expect(find.text(_en.dashboardTodayNeedsMarkingDetail(3)), findsOneWidget);
    expect(find.text(_en.dashboardTodayGoToMarking), findsOneWidget);

    // Live now: the first test, its time left and who is taking it.
    expect(find.text('Algebra quiz'), findsOneWidget);
    expect(
      find.text(_en.dashboardTodayTimeLeft(OrgTime.clock(125, 'en'))),
      findsOneWidget,
    );
    expect(
      find.text(
        '${_en.dashboardTodayParticipants(30)} · '
        '${_en.dashboardTodaySubmitted(12)}',
      ),
      findsOneWidget,
    );
    expect(find.text(_en.dashboardTodayLiveOf(1, 2)), findsOneWidget);

    // Starting soon: the soonest test, whatever the server's order.
    final soon = find.byKey(const Key('tile-soon'));
    expect(
      find.descendant(of: soon, matching: find.text('Fractions')),
      findsOneWidget,
    );
  });

  testWidgets('the live test counts down; previous and next', (tester) async {
    await pumpInstructorApp(
      tester,
      api: _api((_) => ok(_full())),
      session: _teacher(),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.text(_en.dashboardTodayTimeLeft(OrgTime.clock(123, 'en'))),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('live-next')));
    await tester.pump();
    expect(find.text('Geometry quiz'), findsOneWidget);
    expect(find.text(_en.dashboardTodayLiveOf(2, 2)), findsOneWidget);
    await tester.tap(find.byKey(const Key('live-next')));
    await tester.pump();
    expect(find.text('Algebra quiz'), findsOneWidget);
  });

  testWidgets('upcoming tests, students, classes and top students', (
    tester,
  ) async {
    await pumpInstructorApp(
      tester,
      api: _api((_) => ok(_full())),
      session: _teacher(),
    );

    await _scrollTo(tester, find.byKey(const Key('upcoming-u2')));
    expect(find.byKey(const Key('upcoming-u1')), findsOneWidget);
    expect(
      find.textContaining(_en.dashboardDurationHoursMinutes(1, 30)),
      findsOneWidget,
    );
    expect(
      find.textContaining(_en.dashboardDurationMinutes(45)),
      findsOneWidget,
    );

    await _scrollTo(tester, find.byKey(const Key('students-pending')));
    expect(
      find.descendant(
        of: find.byKey(const Key('students-total')),
        matching: find.text('55'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('students-active')),
        matching: find.text('48'),
      ),
      findsOneWidget,
    );

    await _scrollTo(tester, find.byKey(const Key('class-c2')));
    expect(find.text(_en.dashboardClassesTooltip(30)), findsWidgets);

    // Top students: best first, 10 shown, the rest counted.
    await _scrollTo(tester, find.byKey(const Key('top-s2')));
    double y(String id) => tester.getTopLeft(find.byKey(Key('top-$id'))).dy;
    expect(y('s2'), lessThan(y('s1')));
    expect(find.byKey(const Key('top-s3')), findsNothing);
    await _scrollTo(tester, find.text(_en.dashboardTopMore(2)));
  });

  testWidgets('top students: search and another class', (tester) async {
    await pumpInstructorApp(
      tester,
      api: _api((_) => ok(_full())),
      session: _teacher(),
    );
    await _scrollTo(tester, find.byKey(const Key('top-search')));
    await tester.enterText(find.byKey(const Key('top-search')), 'nadia');
    await tester.pump();
    expect(find.byKey(const Key('top-s2')), findsOneWidget);
    expect(find.byKey(const Key('top-s1')), findsNothing);

    await tester.enterText(find.byKey(const Key('top-search')), 'zzz');
    await tester.pump();
    expect(find.text(_en.dashboardTopNoMatch), findsOneWidget);

    await _scrollTo(tester, find.byKey(const Key('top-class')));
    await tester.tap(find.byKey(const Key('top-class')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Class 7 B').last);
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('top-s20')));
    expect(find.byKey(const Key('top-s20')), findsOneWidget);
  });

  testWidgets('nothing yet: the empty states, no marking button', (
    tester,
  ) async {
    await pumpInstructorApp(
      tester,
      api: _api((_) => ok(_empty())),
      session: _teacher(),
    );
    expect(find.text(_en.dashboardTodayNeedsMarkingDetail(0)), findsOneWidget);
    expect(find.text(_en.dashboardTodayGoToMarking), findsNothing);
    expect(find.text(_en.dashboardTodayNoLive), findsOneWidget);
    expect(find.text(_en.dashboardTodayNothingScheduled), findsOneWidget);
    await _scrollTo(tester, find.text(_en.dashboardUpcomingEmpty));
    await _scrollTo(tester, find.text(_en.dashboardStudentsEmpty));
    await _scrollTo(tester, find.text(_en.dashboardTopEmpty));
  });

  testWidgets('a failure says so; Retry loads again', (tester) async {
    var calls = 0;
    await pumpInstructorApp(
      tester,
      api: _api((_) => ++calls == 1 ? apiError(500) : ok(_empty())),
      session: _teacher(),
    );
    expect(find.text(_en.dashboardLoadFailed), findsOneWidget);
    await tester.tap(find.text(_en.uiErrorRetry));
    await tester.pumpAndSettle();
    expect(find.text(_en.dashboardTodayNoLive), findsOneWidget);
  });

  testWidgets('Today is one tap away; /dashboard comes home', (tester) async {
    final app = await pumpInstructorApp(
      tester,
      api: _api((_) => ok(_full())),
      session: _teacher(),
    );
    await tester.tap(find.byKey(const Key('open-today')));
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);

    // The web's /dashboard link comes back home.
    app.read(routerProvider).go(AppRoutes.dashboard);
    await tester.pumpAndSettle();
    expect(find.byType(TeacherDashboardScreen), findsOneWidget);
  });

  testWidgets('students keep Today as home', (tester) async {
    final app = await pumpInstructorApp(
      tester,
      api: _api((_) => ok(_full())),
      session: testSession(),
    );
    expect(find.byType(TodayScreen), findsOneWidget);
    app.read(routerProvider).go(AppRoutes.dashboard);
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla: one column, nothing cut off', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpInstructorApp(
      tester,
      api: _api((_) => ok(_full())),
      session: _teacher(),
      prefs: {'language': 'bn'},
    );
    await tester.tap(find.byKey(const Key('live-next')));
    await tester.pump();
    await _scrollTo(tester, find.byKey(const Key('top-search')));
    await _scrollTo(tester, find.byKey(const Key('top-s2')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('in Bangla, with Bangla digits', (tester) async {
    final bn = AppLocalizationsBn();
    await pumpInstructorApp(
      tester,
      api: _api((_) => ok(_full())),
      session: _teacher(),
      prefs: {'language': 'bn'},
    );
    expect(find.text(bn.dashboardTodayNeedsMarking), findsOneWidget);
    expect(find.text(bn.dashboardTodayNeedsMarkingDetail(3)), findsOneWidget);
    expect(find.text('৩'), findsOneWidget);
  });
}

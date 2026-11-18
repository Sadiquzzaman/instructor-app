import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/features/calendar/data/calendar_feed.dart';
import 'package:instructor_app/features/attendance/screens/my_attendance_screen.dart';
import 'package:instructor_app/features/today/screens/today_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();
final _today = OrgTime.today();

/// An instant on [day] at [hhmm] Dhaka time.
String _at(String day, String hhmm) => '${day}T$hhmm:00+06:00';

const _here = {'key': 'org:org-1', 'label': 'Demo School'};
const _there = {'key': 'org:org-9', 'label': 'Sunrise School'};

List<Map<String, Object?>> _items() => [
  {
    'kind': 'HOLIDAY',
    'id': 'off',
    'date': _today,
    'title': null,
    'reason': 'WEEKLY_OFF',
  },
  {
    'kind': 'CLASS',
    'id': 'c1',
    'date': _today,
    'starts_at': _at(_today, '00:00'),
    'ends_at': _at(_today, '23:59'),
    'title': 'Class 6 A',
    'section': {'id': 's1', 'name': 'A', 'class_name': 'Class 6'},
    'subject': 'English',
    'teacher': 'Karim Uddin',
    'room': 'Room 4',
    'role': 'STUDENT',
    'status': 'OPEN',
    'workspace': _here,
  },
  {
    'kind': 'EVENT',
    'id': 'e1',
    'starts_at': _at(_today, '14:00'),
    'ends_at': _at(_today, '15:00'),
    'title': 'Science fair',
    'event_type': 'ACTIVITY',
    'place': 'Hall',
    'cancelled': false,
    'workspace': _there,
  },
  {
    'kind': 'HOMEWORK',
    'id': 'h1',
    'starts_at': _at(addDays(_today, 1), '20:00'),
    'ends_at': _at(addDays(_today, 1), '20:00'),
    'title': 'Chapter 3 exercises',
    'subject': 'English',
    'sections': ['Class 6 A'],
    'handed_in': false,
    'workspace': _here,
  },
  {
    'kind': 'HOMEWORK',
    'id': 'h2',
    'starts_at': _at(addDays(_today, 2), '20:00'),
    'ends_at': _at(addDays(_today, 2), '20:00'),
    'title': 'Essay',
    'subject': 'Bangla',
    'sections': ['Class 6 A'],
    'handed_in': true,
    'workspace': _here,
  },
  {
    'kind': 'EXAM',
    'id': 'x1',
    'starts_at': _at(addDays(_today, 3), '10:00'),
    'ends_at': _at(addDays(_today, 3), '11:00'),
    'title': 'Maths monthly test',
    'class_name': 'Class 6',
    'workspace': _here,
  },
  {
    'kind': 'EVENT',
    'id': 'e2',
    'starts_at': _at(addDays(_today, 4), '10:00'),
    'ends_at': _at(addDays(_today, 4), '11:00'),
    'title': 'Called-off trip',
    'event_type': 'OTHER',
    'place': null,
    'cancelled': true,
    'workspace': _here,
  },
  {'kind': 'SOMETHING_NEW', 'id': 'z'},
];

FakeApi _api({FakeHandler? calendar}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on(
    'GET /calendar/me',
    calendar ??
        (_) => ok({
          'from': _today,
          'to': addDays(_today, 7),
          'time_zone': 'Asia/Dhaka',
          'items': _items(),
          'workspaces': [_here, _there],
        }),
  );

Finder _scrollable() => find
    .descendant(of: find.byType(TodayScreen), matching: find.byType(Scrollable))
    .first;

void main() {
  test('the feed reads every kind and skips what it cannot place', () {
    final feed = CalendarFeed.fromJson({'items': _items()});
    expect(feed.items, hasLength(7)); // the unknown kind is left out
    final c = feed.items.firstWhere((i) => i.id == 'c1');
    expect(c.kind, CalendarKind.classItem);
    expect(c.sectionName, 'A');
    expect(c.workspace?.label, 'Demo School');
    expect(feed.items.first.kind, CalendarKind.holiday); // closed days first
    expect(CalendarItem.fromJson({'kind': 'EXAM', 'id': 'x'}), isNull);
    expect(CalendarItem.fromJson({'kind': 'HOLIDAY', 'id': 'h'}), isNull);
    expect(addDays('2026-12-30', 3), '2027-01-02');
    expect(calendarKeyOf(testSession()), 'org:org-1');
  });

  testWidgets('today: check-in open, the day, due this week, coming up', (
    tester,
  ) async {
    final api = _api();
    await pumpInstructorApp(tester, api: api, session: testSession());
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(api.to('GET /calendar/me').single.query, {
      'from': _today,
      'to': addDays(_today, 7),
    });
    expect(
      find.text(_en.todayCheckInOpen('English · Class 6 A')),
      findsOneWidget,
    );
    // The weekly day off is not listed; the class and event are.
    expect(find.text(_en.calendarClosedWEEKLYOFF), findsNothing);
    expect(find.text('English · Class 6 A'), findsOneWidget);
    // Two workspaces: each item names its own.
    expect(find.text('Karim Uddin · Room 4 · Demo School'), findsOneWidget);
    expect(find.text('Hall · Sunrise School'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text(_en.todayOpenCalendar),
      200,
      scrollable: _scrollable(),
    );
    // Due: only what is not handed in yet.
    expect(find.text(_en.calendarDue('Chapter 3 exercises')), findsOneWidget);
    expect(find.text(_en.calendarDue('Essay')), findsNothing);
    expect(find.text(_en.calendarNotHandedIn), findsOneWidget);
    // Coming up: the exam, not the cancelled event.
    expect(find.text('Maths monthly test'), findsOneWidget);
    expect(find.text('Called-off trip'), findsNothing);
    // A student has no "Your school" card.
    expect(find.text(_en.todaySchoolTitle), findsNothing);
  });

  testWidgets('Check in opens My attendance', (tester) async {
    await pumpInstructorApp(tester, api: _api(), session: testSession());
    await tester.tap(find.text(_en.todayCheckIn));
    await tester.pumpAndSettle();
    expect(find.byType(MyAttendanceScreen), findsOneWidget);
  });

  testWidgets('an item opens its details; another workspace says so', (
    tester,
  ) async {
    await pumpInstructorApp(tester, api: _api(), session: testSession());
    await tester.tap(find.text('English · Class 6 A'));
    await tester.pumpAndSettle();
    expect(find.text(_en.calendarDetailsTeacher), findsOneWidget);
    expect(find.text('Room 4'), findsOneWidget);
    expect(find.text(_en.calendarOtherWorkspace('Demo School')), findsNothing);
    Navigator.of(tester.element(find.text('Room 4'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Science fair'));
    await tester.pumpAndSettle();
    expect(
      find.text(_en.calendarOtherWorkspace('Sunrise School')),
      findsOneWidget,
    );
  });

  testWidgets('without the calendar in any workspace it says so', (
    tester,
  ) async {
    await pumpInstructorApp(
      tester,
      api: _api(
        calendar: (_) => ok({'items': <Object>[], 'workspaces': <Object>[]}),
      ),
      session: testSession(),
    );
    expect(find.text(_en.todayNoCalendar), findsOneWidget);
    expect(find.text(_en.todayNothingDue), findsOneWidget);
  });

  testWidgets('a failed load can be retried', (tester) async {
    var calls = 0;
    await pumpInstructorApp(
      tester,
      api: _api(
        calendar: (_) => calls++ == 0
            ? apiError(500)
            : ok({
                'items': _items(),
                'workspaces': [_here],
              }),
      ),
      session: testSession(),
    );
    expect(find.text(_en.todayLoadFailed), findsOneWidget);
    await tester.tap(find.text(_en.uiErrorRetry));
    await tester.pumpAndSettle();
    expect(find.text(_en.todayLoadFailed), findsNothing);
    expect(
      find.text(_en.todayCheckInOpen('English · Class 6 A')),
      findsOneWidget,
    );
  });

  testWidgets('an owner also gets "Your school"', (tester) async {
    final p = sessionPayload();
    final owner = Session.fromPayload({
      ...p,
      'role': 'TEACHER',
      'organization': <String, dynamic>{
        ...p['organization'] as Map<String, dynamic>,
        'role': 'OWNER',
      },
    });
    final app = await pumpInstructorApp(tester, api: _api(), session: owner);
    // A teacher's home is the dashboard; Today is its own page.
    app.read(routerProvider).go(AppRoutes.today);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(_en.todaySchoolTitle),
      200,
      scrollable: _scrollable(),
    );
    expect(find.text(_en.todayOpenOverview), findsOneWidget);
  });

  testWidgets('in Bangla', (tester) async {
    final bn = AppLocalizationsBn();
    await pumpInstructorApp(
      tester,
      api: _api(),
      session: testSession(),
      prefs: {'language': 'bn'},
    );
    expect(find.text(bn.todaySchedule), findsOneWidget);
    expect(find.text(bn.todayCheckIn), findsOneWidget);
  });
}

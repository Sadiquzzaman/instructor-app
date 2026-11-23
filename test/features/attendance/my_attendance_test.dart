import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/location/locator.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/attendance/data/my_attendance.dart';
import 'package:instructor_app/features/attendance/screens/my_attendance_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Map<String, Object?> _class(
  String id, {
  String subject = 'Mathematics',
  String type = 'IN_PERSON',
  String state = 'OPEN',
  bool canCheckIn = true,
  String? blocked,
  String mode = 'SELF_CHECK_IN',
  String role = 'STUDENT',
  Map<String, Object?>? record,
}) => {
  'slot_id': id,
  'date': '2026-11-18',
  'role': role,
  'section': {'id': 's1', 'name': 'A', 'class_name': 'Class 6'},
  'subject': {'id': 'sub', 'name': subject},
  'class_type': type,
  'mode': mode,
  'start_time': '10:00:00',
  'end_time': '10:45:00',
  'opens_at': '2026-11-18T03:45:00.000Z',
  'starts_at': '2026-11-18T04:00:00.000Z',
  'late_after': '2026-11-18T04:05:00.000Z',
  'ends_at': '2026-11-18T04:45:00.000Z',
  'state': state,
  'needs_location': type == 'IN_PERSON',
  'blocked': blocked,
  'can_check_in': canCheckIn,
  'record': record,
};

Map<String, Object?> _today({
  List<Map<String, Object?>>? classes,
  bool onLeave = false,
}) => {
  'date': '2026-11-18',
  'server_time': '2026-11-18T04:01:00.000Z',
  'time_zone': 'Asia/Dhaka',
  'closed': null,
  'on_leave': onLeave,
  'classes':
      classes ??
      [
        _class('online', subject: 'English', type: 'ONLINE'),
        _class('room', subject: 'Science'),
        _class(
          'later',
          subject: 'History',
          state: 'UPCOMING',
          canCheckIn: false,
        ),
        _class(
          'paper',
          subject: 'Art',
          state: 'CLOSED',
          canCheckIn: false,
          blocked: 'PAPER_REGISTER',
          mode: 'PAPER_REGISTER',
        ),
        _class(
          'mine',
          subject: 'Physics',
          role: 'TEACHER',
          state: 'CLOSED',
          canCheckIn: false,
          record: {'status': 'LATE', 'late_minutes': 7, 'flag': null},
        ),
      ],
};

Map<String, Object?> _month(String month) => {
  'month': month,
  'today': '2026-11-18',
  'time_zone': 'Asia/Dhaka',
  'days': [
    {
      'date': '$month-01',
      'closed': {'date': '$month-01', 'reason': 'WEEKLY_OFF'},
      'classes': <Object>[],
    },
    {
      'date': '$month-02',
      'closed': null,
      'classes': [
        {
          'slot_id': 'x',
          'role': 'STUDENT',
          'section': {'id': 's1', 'name': 'A', 'class_name': 'Class 6'},
          'subject': {'id': 'm', 'name': 'Mathematics'},
          'start_time': '10:00:00',
          'end_time': '10:45:00',
          'status': 'PRESENT',
          'record': null,
        },
      ],
    },
  ],
  'counts': {'present': 12, 'late': 2, 'absent': 1, 'leave': 0},
  'attendance_pct': 93.3,
};

class _FakeLocator implements Locator {
  _FakeLocator([this.problem]);
  LocationProblem? problem;
  LocationProblem? opened;

  @override
  Future<LocationFix> currentFix() async {
    if (problem != null) throw LocationException(problem!);
    return (latitude: 23.7577, longitude: 90.3897, accuracy: 18.0);
  }

  @override
  Future<void> openSettings(LocationProblem p) async => opened = p;
}

FakeApi _api({FakeHandler? today, FakeHandler? checkIn}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /calendar/me', (_) => ok({'items': <Object>[]}))
  ..on('GET /attendance/me/today', today ?? (_) => ok(_today()))
  ..on(
    'GET /attendance/me/calendar',
    (r) => ok(_month((r.query['month'] as String?) ?? '2026-11')),
  )
  ..on(
    'POST /attendance/check-in',
    checkIn ??
        (r) => ok(
          _class(
            (r.body! as Map)['slot_id'] as String,
            subject: 'English',
            type: 'ONLINE',
            state: 'OPEN',
            canCheckIn: false,
            record: {'status': 'PRESENT', 'late_minutes': 0},
          ),
        ),
  );

/// The app with a stand-in for the phone's location, on My attendance.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeApi api, {
  Locator? locator,
  String? lang,
}) async {
  final c = await pumpInstructorApp(
    tester,
    api: api,
    session: testSession(),
    prefs: {'language': ?lang},
    overrides: [locatorProvider.overrideWithValue(locator ?? _FakeLocator())],
  );
  c.read(routerProvider).go(AppRoutes.myAttendance);
  await tester.pumpAndSettle();
  return c;
}

Finder _row(String id, Finder f) =>
    find.descendant(of: find.byKey(Key('class-$id')), matching: f);

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    200,
    scrollable: find
        .descendant(
          of: find.byType(MyAttendanceScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  test('a class shows its record, its window, or why it has none', () {
    MyClass c(Map<String, Object?> j) => MyClass.fromJson(j)!;
    expect(c(_class('a')).status, 'OPEN');
    expect(c(_class('a', state: 'UPCOMING')).status, 'UPCOMING');
    expect(c(_class('a', state: 'CLOSED')).status, 'ABSENT');
    expect(
      c(_class('a', state: 'CLOSED', mode: 'PAPER_REGISTER')).status,
      'NOT_RECORDED',
    );
    expect(c(_class('a', blocked: 'CANCELLED')).status, 'CANCELLED');
    expect(
      c(_class('a', record: {'status': 'LEAVE'}, blocked: 'CLOSED_DAY')).status,
      'LEAVE',
    );
    expect(c(_class('a')).label, 'Mathematics · Class 6 A');
    expect(
      classLabelOf({'class_name': 'Class 6', 'name': 'A'}, null),
      'Class 6 A',
    );
    expect(shiftMonth('2026-01', -1), '2025-12');
    expect(shiftMonth('2026-12', 1), '2027-01');
    final m = MyCalendar.fromJson(_month('2026-11'));
    expect(m.present, 12);
    expect(m.days.last.marks.single.status, 'PRESENT');
  });

  testWidgets('today\'s classes with their state', (tester) async {
    await _pump(tester, _api());
    expect(find.text('English · Class 6 A'), findsOneWidget);
    expect(_row('online', find.text(_en.myAttendanceCheckIn)), findsOneWidget);
    expect(_row('later', find.text(_en.myAttendanceCheckIn)), findsNothing);
    await _scrollTo(tester, find.byKey(const Key('class-mine')));
    expect(
      _row('paper', find.text(_en.myAttendanceBlockedPAPERREGISTER)),
      findsOneWidget,
    );
    expect(_row('mine', find.text(_en.myAttendanceYouTeach)), findsOneWidget);
    expect(
      _row('mine', find.textContaining(_en.myAttendanceLateBy(7))),
      findsOneWidget,
    );
  });

  testWidgets('an online class checks in without a location', (tester) async {
    final api = _api();
    final locator = _FakeLocator(LocationProblem.denied);
    await _pump(tester, api, locator: locator);
    await tester.tap(_row('online', find.text(_en.myAttendanceCheckIn)));
    await tester.pumpAndSettle();
    expect(api.to('POST /attendance/check-in').single.body, {
      'slot_id': 'online',
    });
    expect(find.text(_en.myAttendanceCheckedIn), findsOneWidget);
    expect(_row('online', find.text(_en.myAttendanceCheckIn)), findsNothing);
    expect(
      _row('online', find.textContaining(_en.myAttendanceStatusPRESENT)),
      findsOneWidget,
    );
  });

  testWidgets('an in-person class sends one location fix', (tester) async {
    final api = _api(
      checkIn: (_) => ok(
        _class(
          'room',
          subject: 'Science',
          canCheckIn: false,
          record: {'status': 'LATE', 'late_minutes': 4},
        ),
      ),
    );
    await _pump(tester, api);
    await tester.tap(_row('room', find.text(_en.myAttendanceCheckIn)));
    await tester.pumpAndSettle();
    expect(api.to('POST /attendance/check-in').single.body, {
      'slot_id': 'room',
      'latitude': 23.7577,
      'longitude': 90.3897,
      'accuracy_m': 18.0,
    });
    expect(find.text(_en.myAttendanceCheckedInLate(4)), findsOneWidget);
  });

  testWidgets('location turned off for the app: says so, opens settings', (
    tester,
  ) async {
    final api = _api();
    final locator = _FakeLocator(LocationProblem.deniedForever);
    await _pump(tester, api, locator: locator);
    await tester.tap(_row('room', find.text(_en.myAttendanceCheckIn)));
    await tester.pumpAndSettle();
    expect(api.to('POST /attendance/check-in'), isEmpty);
    expect(
      _row('room', find.text(_en.appLocationDeniedForever)),
      findsOneWidget,
    );
    await tester.tap(_row('room', find.text(_en.appLocationOpenSettings)));
    expect(locator.opened, LocationProblem.deniedForever);
  });

  testWidgets('too far: the distance and the radius', (tester) async {
    final api = _api(
      checkIn: (_) => (
        400,
        {
          'statusCode': 400,
          'error': true,
          'message': 'Too far',
          'code': 'ATTENDANCE_CHECKIN_TOO_FAR',
          'details': {'distance_m': 412.6, 'radius_m': 150},
        },
      ),
    );
    await _pump(tester, api);
    await tester.tap(_row('room', find.text(_en.myAttendanceCheckIn)));
    await tester.pumpAndSettle();
    expect(
      _row(
        'room',
        find.text(_en.myAttendanceErrorsATTENDANCECHECKINTOOFAR(413, 150)),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Too far'), findsNothing);
  });

  testWidgets('already checked in: says so and reads today again', (
    tester,
  ) async {
    var reads = 0;
    final api = _api(
      today: (_) {
        reads++;
        return ok(_today());
      },
      checkIn: (_) => apiError(409, code: 'ATTENDANCE_CHECKIN_ALREADY'),
    );
    await _pump(tester, api);
    expect(reads, 1);
    await tester.tap(_row('online', find.text(_en.myAttendanceCheckIn)));
    await tester.pumpAndSettle();
    expect(
      find.text(_en.myAttendanceErrorsATTENDANCECHECKINALREADY),
      findsOneWidget,
    );
    expect(reads, 2);
  });

  testWidgets('the month: rate, counts, marks; months move', (tester) async {
    final api = _api();
    await _pump(tester, api);
    await _scrollTo(tester, find.text('93.3%'));
    expect(find.text('93.3%'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    await tester.tap(find.byTooltip(_en.myAttendanceNextMonth));
    await tester.pumpAndSettle();
    expect(api.to('GET /attendance/me/calendar').last.query, {
      'month': '2026-12',
    });
  });

  testWidgets('no classes today; a failed load can be retried', (tester) async {
    var calls = 0;
    await _pump(
      tester,
      _api(
        today: (_) => calls++ == 0
            ? apiError(500)
            : ok(_today(classes: [], onLeave: true)),
      ),
    );
    expect(find.text(_en.myAttendanceLoadFailed), findsOneWidget);
    await tester.tap(find.text(_en.uiErrorRetry).first);
    await tester.pumpAndSettle();
    expect(find.text(_en.myAttendanceNoClassesToday), findsOneWidget);
    expect(find.text(_en.myAttendanceOnLeaveToday), findsOneWidget);
  });

  testWidgets('in Bangla', (tester) async {
    final bn = AppLocalizationsBn();
    await _pump(tester, _api(), lang: 'bn');
    expect(find.text(bn.myAttendanceTitle), findsWidgets);
    expect(find.text(bn.myAttendanceCheckIn), findsWidgets);
  });
}

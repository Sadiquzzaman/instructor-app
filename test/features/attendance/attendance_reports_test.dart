import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/attendance/data/my_attendance.dart';
import 'package:instructor_app/features/attendance/screens/attendance_reports_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Session _teacher() =>
    Session.fromPayload({...sessionPayload(), 'role': 'TEACHER'});

Map<String, Object?> _student(String id, String name, Object? day) => {
  'id': id,
  'full_name': name,
  'roll_no': null,
  'marks': <Object>[],
  'day': day,
};

Map<String, Object?> _daily({List<Object>? sections, Object? closed}) => {
  'date': '2026-11-18',
  'today': '2026-11-18',
  'time_zone': 'Asia/Dhaka',
  'closed': closed,
  'sections':
      sections ??
      [
        {
          'section': {'id': 'sec1', 'name': 'A', 'class_name': 'Class 6'},
          'mode': 'SELF_CHECKIN',
          'classes': [
            {
              'slot_id': 'sl1',
              'start_time': '10:00',
              'end_time': '10:45',
              'teacher': null,
              'state': 'CLOSED',
              'cancelled': false,
              'counts': <String, int>{},
            },
            {
              'slot_id': 'sl2',
              'start_time': '11:00',
              'end_time': '11:45',
              'teacher': null,
              'state': 'CLOSED',
              'cancelled': true,
              'counts': <String, int>{},
            },
          ],
          'counts': {'students': 4},
          'students': [
            _student('s1', 'Karim Hasan', {
              'status': 'ABSENT',
              'missed': 1,
              'waiting': 0,
            }),
            _student('s2', 'Nadia Islam', {
              'status': 'PRESENT',
              'missed': 1,
              'waiting': 0,
            }),
            _student('s3', 'Sami Rahman', {
              'status': 'PRESENT',
              'missed': 0,
              'waiting': 0,
            }),
            _student('s4', 'Tania Akter', null),
          ],
        },
      ],
};

Map<String, Object?> _month({bool empty = false}) => {
  'section': {'id': 'sec1', 'name': 'A', 'class_name': 'Class 6'},
  'month': '2026-11',
  'today': '2026-11-18',
  'mode': 'SELF_CHECKIN',
  'can_import': false,
  'classes': empty
      ? <Object>[]
      : [
          {'header': '2026-11-16', 'date': '2026-11-16'},
          {'header': '2026-11-17', 'date': '2026-11-17'},
        ],
  'days': empty
      ? <Object>[]
      : [
          {'date': '2026-11-16', 'classes': 1},
          {'date': '2026-11-17', 'classes': 1},
        ],
  'students': [
    {
      'id': 's1',
      'full_name': 'Karim Hasan',
      'roll_no': '1',
      'marks': <Object>[],
      'days': [
        {'status': 'PRESENT', 'missed': 0, 'waiting': 0},
        {'status': 'LATE', 'missed': 2, 'waiting': 0},
      ],
      'counts': {'present': 1, 'late': 1, 'absent': 0, 'leave': 0},
      'attendance_pct': 100,
    },
    {
      'id': 's2',
      'full_name': 'Nadia Islam',
      'roll_no': '2',
      'marks': <Object>[],
      'days': [
        null,
        {'status': 'ABSENT', 'missed': 0, 'waiting': 0},
      ],
      'counts': {'present': 0, 'late': 0, 'absent': 1, 'leave': 0},
      'attendance_pct': 0,
    },
  ],
  'counts': {'present': 1, 'late': 1, 'absent': 1, 'leave': 0},
  'attendance_pct': 67,
};

FakeApi _api({
  List<Object>? sections,
  FakeHandler? daily,
  FakeHandler? month,
}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /attendance/register/sections',
    (_) => ok(
      sections ??
          [
            {
              'id': 'sec1',
              'name': 'A',
              'class_name': 'Class 6',
              'mode': 'SELF_CHECKIN',
            },
            {
              'id': 'sec2',
              'name': 'B',
              'class_name': 'Class 7',
              'mode': 'PAPER_REGISTER',
            },
          ],
    ),
  )
  ..on('GET /attendance/reports/daily', daily ?? (_) => ok(_daily()))
  ..on(
    'GET /attendance/reports/sections/sec1/month',
    month ?? (_) => ok(_month()),
  )
  ..on(
    'GET /attendance/reports/sections/sec2/month',
    (_) => ok(_month(empty: true)),
  );

Future<void> _open(WidgetTester tester, FakeApi api, {String? lang}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _teacher(),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go('/attendance-reports');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'daily: each section\'s students by their day, most urgent first',
    (tester) async {
      final api = _api();
      await _open(tester, api);
      expect(find.byType(AttendanceReportsScreen), findsOneWidget);
      expect(find.byKey(const Key('daily-sec1')), findsOneWidget);
      expect(find.textContaining(_en.reportsCancelled), findsOneWidget);
      expect(find.textContaining(_en.registerModeSELFCHECKIN), findsOneWidget);
      // Absent all day; came but missed one; present. No class: no group.
      expect(find.byKey(const Key('group-sec1-ABSENT')), findsOneWidget);
      expect(find.byKey(const Key('group-sec1-MISSED_SOME')), findsOneWidget);
      expect(find.byKey(const Key('group-sec1-PRESENT')), findsOneWidget);
      expect(find.byKey(const Key('group-sec1-LATE')), findsNothing);
      expect(
        find.text('Nadia Islam (${_en.reportsMissedShort(1)})'),
        findsOneWidget,
      );
      expect(find.textContaining('Tania Akter'), findsNothing);
      double y(String g) =>
          tester.getTopLeft(find.byKey(Key('group-sec1-$g'))).dy;
      expect(y('ABSENT'), lessThan(y('MISSED_SOME')));
      expect(y('MISSED_SOME'), lessThan(y('PRESENT')));
      // Today and all sections unless chosen.
      final q = api.to('GET /attendance/reports/daily').single.query;
      expect(q['date'], isNull);
      expect(q['section_id'], isNull);
    },
  );

  testWidgets('daily: one section asks for it', (tester) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('report-section')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Class 7 B').last);
    await tester.pumpAndSettle();
    expect(
      api.to('GET /attendance/reports/daily').last.query['section_id'],
      'sec2',
    );
  });

  testWidgets('daily: a holiday with no classes says so', (tester) async {
    await _open(
      tester,
      _api(
        daily: (_) => ok(
          _daily(
            sections: [],
            closed: {'date': '2026-11-18', 'reason': 'HOLIDAY'},
          ),
        ),
      ),
    );
    expect(find.text(_en.reportsClosedHOLIDAY), findsOneWidget);
  });

  testWidgets('monthly: the grid with marks, counts and %; months move', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('tab-monthly')));
    await tester.pumpAndSettle();
    final month = OrgTime.today().substring(0, 7);
    expect(api.to('GET /attendance/reports/sections/sec1/month').single.query, {
      'month': month,
    });
    expect(find.byKey(const Key('month-grid')), findsOneWidget);
    expect(find.text('Karim Hasan'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    // Missed two classes on a late day: a small 2.
    expect(find.text('2'), findsWidgets);

    await tester.tap(find.byKey(const Key('month-previous')));
    await tester.pumpAndSettle();
    expect(api.to('GET /attendance/reports/sections/sec1/month').last.query, {
      'month': shiftMonth(month, -1),
    });
  });

  testWidgets('monthly: a section with no class days', (tester) async {
    await _open(tester, _api());
    await tester.tap(find.byKey(const Key('tab-monthly')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-section')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Class 7 B').last);
    await tester.pumpAndSettle();
    expect(find.text(_en.reportsNoClasses), findsOneWidget);
  });

  testWidgets('no sections to show: the empty state, no tabs', (tester) async {
    await _open(tester, _api(sections: []));
    expect(find.byType(EmptyView), findsOneWidget);
    expect(find.byKey(const Key('tab-daily')), findsNothing);
  });

  testWidgets('a refusal and a locked plan', (tester) async {
    await _open(
      tester,
      _api(
        daily: (_) =>
            apiError(403, code: 'ATTENDANCE_REPORT_SECTION_NOT_FOUND'),
      ),
    );
    expect(find.text(_en.reportsLoadFailed), findsOneWidget);
    expect(find.textContaining('not one you can see'), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.reportsTitle), findsOneWidget);
    await tester.tap(find.byKey(const Key('tab-monthly')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('month-grid')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

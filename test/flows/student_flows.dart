import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/files/file_picking.dart';
import 'package:instructor_app/core/files/local_file.dart';
import 'package:instructor_app/core/location/locator.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/features/attendance/screens/my_attendance_screen.dart';
import 'package:instructor_app/features/auth/screens/login_screen.dart';
import 'package:instructor_app/features/homework/screens/homework_detail_screen.dart';
import 'package:instructor_app/features/tests/data/exam_live.dart';
import 'package:instructor_app/features/tests/data/take_test.dart';
import 'package:instructor_app/features/tests/screens/take_test_screen.dart';
import 'package:instructor_app/features/today/screens/today_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

/// A student's main flows, end to end through the app's own screens, against
/// the in-process fake API (no network, no password). Run by `flutter test`
/// (test/flows) and on a device by `flutter test integration_test`.
void studentFlows() {
  testWidgets('sign in, Today, check in to an open class', (tester) async {
    final api = _school()
      ..on('POST /auth/login', (_) => ok(sessionPayload()))
      ..on('POST /attendance/check-in', (r) {
        final slot = (r.body! as Map)['slot_id'] as String;
        return ok(_slot(slot, checkedIn: true));
      });
    await pumpInstructorApp(
      tester,
      api: api,
      prefs: {'language': 'en'},
      overrides: [locatorProvider.overrideWithValue(_Here())],
    );
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.enterText(_field('login-identifier'), '01100000001');
    await tester.enterText(_field('login-password'), 'a-test-value');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byKey(const Key('check-in-open')), findsOneWidget);
    await tester.tap(find.text(_en.todayCheckIn));
    await tester.pumpAndSettle();

    expect(find.byType(MyAttendanceScreen), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('class-slot1')),
        matching: find.text(_en.myAttendanceCheckIn),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.to('POST /attendance/check-in').single.body, {
      'slot_id': 'slot1',
    });
    expect(find.text(_en.myAttendanceCheckedIn), findsOneWidget);
  });

  testWidgets('hand in homework: a typed answer and a photo', (tester) async {
    var handedIn = false;
    final api = _school()
      ..on('GET /homework/h1/my-submissions', (_) => ok(_mine(handedIn)))
      ..on('POST /homework/h1/submissions', (_) {
        handedIn = true;
        return ok(_mine(true));
      });
    final c = await pumpInstructorApp(
      tester,
      api: api,
      session: testSession(),
      prefs: {'language': 'en'},
      overrides: [filePickingProvider.overrideWithValue(_Picking())],
    );
    c.read(routerProvider).go(AppRoutes.homework);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('homework-h1')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeworkDetailScreen), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('homework-answer')),
        matching: find.byType(TextField),
      ),
      'My answer',
    );
    await _scrollTo(tester, HomeworkDetailScreen, const Key('attach'));
    await tester.tap(find.byKey(const Key('attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.appAttachChoosePhotos));
    await tester.pumpAndSettle();
    await _scrollTo(tester, HomeworkDetailScreen, const Key('homework-submit'));
    await tester.tap(find.byKey(const Key('homework-submit')));
    await tester.pumpAndSettle();

    expect(api.to('PUT /b/f1'), hasLength(1));
    expect(api.to('POST /homework/h1/submissions').single.body, {
      'file_ids': ['f1'],
      'text_answer': 'My answer',
    });
    await _scrollTo(tester, HomeworkDetailScreen, const Key('version-1'));
    expect(find.text(_en.homeworkMyWorkVersion(1)), findsOneWidget);
  });

  testWidgets('take a test from the Tests list and submit it', (tester) async {
    final api = _school();
    final c = await pumpInstructorApp(
      tester,
      api: api,
      session: testSession(),
      prefs: {'language': 'en'},
      overrides: [examLiveProvider.overrideWithValue(_Live())],
    );
    c.read(routerProvider).go(AppRoutes.tests);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('test-x1')),
        matching: find.text(_en.testsCardStart),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TakeTestScreen), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('accept-rules')));
    await tester.tap(find.byKey(const Key('accept-rules')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('start-test')));
    await tester.tap(find.byKey(const Key('start-test')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('choice-b')));
    await tester.pump();
    await _scrollTo(tester, TakeTestScreen, const Key('answer-q2'));
    await tester.enterText(find.byKey(const Key('answer-q2')), 'Because.');
    await tester.pump(saveAfter);
    await tester.pumpAndSettle();
    expect(api.to('PUT /student/exams/x1/answersheet'), isNotEmpty);

    await _scrollTo(tester, TakeTestScreen, const Key('submit-test'));
    await tester.tap(find.byKey(const Key('submit-test')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.examSubmitConfirm));
    await tester.pumpAndSettle();
    final body =
        api.to('POST /student/exams/x1/answersheet').single.body! as Map;
    expect(body['answersheet'], {
      'q1': ['b'],
      'q2': 'Because.',
    });
    expect(find.text(_en.examMessageAlreadySubmittedTitle), findsOneWidget);
    // End the screen so its timers stop.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
  });
}

final _en = AppLocalizationsEn();
final _today = OrgTime.today();

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

Future<void> _scrollTo(WidgetTester tester, Type screen, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    200,
    scrollable: find
        .descendant(of: find.byType(screen), matching: find.byType(Scrollable))
        .first,
  );
  await tester.pumpAndSettle();
}

/// One open, online class today.
Map<String, Object?> _slot(String id, {bool checkedIn = false}) => {
  'slot_id': id,
  'date': _today,
  'role': 'STUDENT',
  'section': {'id': 's1', 'name': 'A', 'class_name': 'Class 6'},
  'subject': {'id': 'e', 'name': 'English'},
  'class_type': 'ONLINE',
  'mode': 'SELF_CHECK_IN',
  'start_time': '00:00:00',
  'end_time': '23:59:00',
  'opens_at': '${_today}T00:00:00+06:00',
  'starts_at': '${_today}T00:00:00+06:00',
  'late_after': '${_today}T23:00:00+06:00',
  'ends_at': '${_today}T23:59:00+06:00',
  'state': 'OPEN',
  'needs_location': false,
  'blocked': null,
  'can_check_in': !checkedIn,
  'record': checkedIn ? {'status': 'PRESENT', 'late_minutes': 0} : null,
};

Map<String, Object?> _homework() => {
  'id': 'h1',
  'title': 'Chapter 3 exercises',
  'instructions': {'html': '<p>Do 1–5.</p>'},
  'submission_type': 'TEXT',
  'total_marks': 10,
  'due_at': DateTime.now()
      .add(const Duration(days: 3))
      .toUtc()
      .toIso8601String(),
  'status': 'PUBLISHED',
  'subject': {'id': 'e', 'name': 'English'},
  'targets': <Object>[],
  'attachments': <Object>[],
  'student_count': 0,
  'can_edit': false,
  'my_submission': null,
};

Map<String, Object?> _mine(bool handedIn) => {
  'submissions': [
    if (handedIn)
      {
        'id': 's1',
        'version': 1,
        'text_answer': 'My answer',
        'submitted_at': DateTime.now().toUtc().toIso8601String(),
        'is_late': false,
        'late_minutes': null,
        'status': 'SUBMITTED',
        'files': [
          {'id': 'f1', 'name': 'page.jpg', 'mime': 'image/jpeg'},
        ],
      },
  ],
  'can_submit': !handedIn,
  'blocked_by': null,
  'submissions_left': handedIn ? 1 : 2,
  'late_now': false,
  'max_files': 5,
  'score': null,
};

Map<String, Object?> _paper() => {
  'id': 'x1',
  'test_name': 'Unit test',
  'status': 'ongoing',
  'remaining_time_seconds': 1800,
  'subjects': [
    {
      'id': 's',
      'name': 'Maths',
      'questions': [
        {
          'id': 'q1',
          'type': 'graded',
          'subType': 'multiple-choice',
          'text': '2 + 2 = ?',
          'points': 1,
          'sortOrder': 1,
          'options': [
            {'id': 'a', 'text': 'Three'},
            {'id': 'b', 'text': 'Four'},
          ],
        },
        {
          'id': 'q2',
          'type': 'graded',
          'subType': 'essay',
          'text': 'Explain.',
          'points': 3,
          'sortOrder': 2,
        },
      ],
    },
  ],
};

/// The school as the API answers it, for one student.
FakeApi _school() => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on(
    'GET /calendar/me',
    (_) => ok({
      'from': _today,
      'to': _today,
      'time_zone': 'Asia/Dhaka',
      'items': [
        {
          'kind': 'CLASS',
          'id': 'slot1',
          'date': _today,
          'starts_at': '${_today}T00:00:00+06:00',
          'ends_at': '${_today}T23:59:00+06:00',
          'title': 'Class 6 A',
          'section': {'id': 's1', 'name': 'A', 'class_name': 'Class 6'},
          'subject': 'English',
          'teacher': 'Karim Uddin',
          'room': null,
          'role': 'STUDENT',
          'status': 'OPEN',
          'workspace': {'key': 'org:org-1', 'label': 'Demo School'},
        },
      ],
      'workspaces': [
        {'key': 'org:org-1', 'label': 'Demo School'},
      ],
    }),
  )
  ..on(
    'GET /attendance/me/today',
    (_) => ok({
      'date': _today,
      'server_time': DateTime.now().toUtc().toIso8601String(),
      'time_zone': 'Asia/Dhaka',
      'closed': null,
      'on_leave': false,
      'classes': [_slot('slot1')],
    }),
  )
  ..on(
    'GET /attendance/me/calendar',
    (r) => ok({
      'month': r.query['month'] ?? _today.substring(0, 7),
      'today': _today,
      'time_zone': 'Asia/Dhaka',
      'days': <Object>[],
      'counts': {'present': 0, 'late': 0, 'absent': 0, 'leave': 0},
      'attendance_pct': null,
    }),
  )
  ..on('GET /homework/mine', (_) => ok([_homework()]))
  ..on('GET /homework/h1', (_) => ok(_homework()))
  ..on(
    'POST /files/presign',
    (_) => ok({
      'file': {'id': 'f1'},
      'upload': {
        'url': 'https://storage.test/b/f1',
        'headers': {'Content-Type': 'image/jpeg'},
      },
      'storage': {'warning': false},
    }),
  )
  ..on('PUT /b/f1', (_) => (200, null))
  ..on(
    'POST /files/f1/complete',
    (_) => ok({'id': 'f1', 'name': 'page.jpg', 'mime': 'image/jpeg'}),
  )
  ..on(
    'GET /student/exams/assigned',
    (_) => ok([
      {
        'id': 'x1',
        'test_name': 'Unit test',
        'subject': 'Mathematics',
        'test_audience': 'selected_class',
        'duration_minutes': 30,
        'exam_start_time': DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toUtc()
            .toIso8601String(),
        'exam_end_time': DateTime.now()
            .add(const Duration(hours: 1))
            .toUtc()
            .toIso8601String(),
        'class_id': 'c1',
        'class_name': 'Class 6',
        'status': 'ongoing',
        'participant_count': 4,
        'submitted_count': 0,
        'exam_category': 'ACADEMIC',
      },
    ]),
  )
  ..on(
    'GET /student/exams/x1/eligibility',
    (_) => ok({
      'eligible': true,
      'can_access': true,
      'reason_code': 'OK',
      'proctoring': {
        'level': 'OFF',
        'checks': <String>[],
        'camera': false,
        'auto_disqualify': null,
      },
    }),
  )
  ..on(
    'POST /student/exams/x1/start',
    (_) => (
      201,
      {
        'statusCode': 201,
        'payload': {'id': 'att'},
      },
    ),
  )
  ..on('GET /exams/x1', (_) => ok(_paper()))
  ..on('PUT /student/exams/x1/answersheet', (_) => ok(null))
  ..on(
    'POST /student/exams/x1/answersheet',
    (_) => ok({'status': 'SUBMITTED'}),
  );

class _Here implements Locator {
  @override
  Future<LocationFix> currentFix() async =>
      (latitude: 23.7577, longitude: 90.3897, accuracy: 18.0);
  @override
  Future<void> openSettings(LocationProblem p) async {}
}

class _Picking implements FilePicking {
  @override
  Future<LocalFile?> takePhoto() async => LocalFile.bytes('page.jpg', [1, 2]);
  @override
  Future<List<LocalFile>> choosePhotos({int? limit}) async => [
    LocalFile.bytes('page.jpg', [1, 2]),
  ];
  @override
  Future<List<LocalFile>> chooseFiles(List<String> extensions) async => [];
}

class _Live implements ExamLive {
  final _events = StreamController<TeacherEvent>.broadcast();
  @override
  Stream<TeacherEvent> get events => _events.stream;
  @override
  void join(String examId) {}
  @override
  void flag(String examId, ProctorFlag flag) {}
  @override
  void submit(
    String examId, {
    required String studentId,
    required String studentName,
    required Map<String, Object> answers,
    required int totalFlagPoints,
  }) {}
  @override
  void dispose() {}
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/attendance/screens/class_attendance_screen.dart';
import 'package:instructor_app/features/auth/screens/login_screen.dart';
import 'package:instructor_app/features/dashboard/screens/teacher_dashboard_screen.dart';
import 'package:instructor_app/features/homework/screens/staff_homework_screens.dart';
import 'package:instructor_app/features/tests/screens/grading_screens.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

/// A teacher's main flows (Stage 2 plan, PR 15), end to end through the
/// app's own screens, against the in-process fake API (no network, no
/// password): take attendance, approve leave, set and mark homework, mark a
/// test. Run by `flutter test` (test/flows) and on a device by
/// `flutter test integration_test`.
void teacherFlows() {
  testWidgets('sign in, the dashboard, correct a class\'s attendance', (
    tester,
  ) async {
    final api = _school()
      ..on('POST /auth/login', (_) => ok({...sessionPayload(), ..._rina}));
    final c = await pumpInstructorApp(
      tester,
      api: api,
      prefs: {'language': 'en'},
    );
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.enterText(_field('login-identifier'), '01100000001');
    await tester.enterText(_field('login-password'), 'a-test-value');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(TeacherDashboardScreen), findsOneWidget);

    await _go(tester, c, '/attendance');
    await tester.tap(find.byKey(const Key('session-$_slot')));
    await tester.pumpAndSettle();
    expect(find.byType(ClassSessionScreen), findsOneWidget);
    await _tap(tester, find.byKey(const Key('correct-s3')));
    await tester.tap(find.byKey(const Key('correction-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.myAttendanceStatusPRESENT).last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('correction-reason')),
      'Phone had no internet',
    );
    await tester.tap(find.byKey(const Key('correction-save')));
    await tester.pumpAndSettle();
    expect(
      api.to('PUT /attendance/sessions/$_slot/$_date/records/s3').single.body,
      {'status': 'PRESENT', 'reason': 'Phone had no internet'},
    );
    expect(
      find.text(_en.classAttendanceCorrected('Sami Rahman')),
      findsOneWidget,
    );
  });

  testWidgets('approve a student\'s leave', (tester) async {
    final api = _school();
    final c = await _signedIn(tester, api);
    await _go(tester, c, '/leave');
    await tester.tap(find.byKey(const Key('tab-approvals')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('approve-w1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('decision-save')));
    await tester.pumpAndSettle();
    expect(api.to('POST /attendance/leave/w1/approve'), hasLength(1));
    expect(find.text(_en.leaveApproved), findsOneWidget);
  });

  testWidgets('set homework for a class, then mark a hand-in', (tester) async {
    final api = _school();
    final c = await _signedIn(tester, api);
    await _go(tester, c, '/homework');
    await tester.tap(find.byKey(const Key('homework-new')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeworkEditorScreen), findsOneWidget);
    await tester.enterText(find.byKey(const Key('editor-title')), 'Ch 3');
    await _tap(tester, find.byKey(const Key('offering-o1')));
    await _tap(tester, find.byKey(const Key('editor-publish')));
    final body = api.to('POST /homework').single.body! as Map;
    expect(body['title'], 'Ch 3');
    expect(body['offering_ids'], ['o1']);
    expect(api.to('POST /homework/h9/publish'), hasLength(1));
    expect(find.text(_en.homeworkPublished), findsOneWidget);

    // A published one with hand-ins: score Karim's.
    await _go(tester, c, '/homework/h1');
    await _tap(tester, find.byKey(const Key('row-s1')));
    expect(find.text('x = 4'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('review-score')), '8');
    await tester.enterText(find.byKey(const Key('review-feedback')), 'Good');
    await _tap(tester, find.byKey(const Key('review-save')));
    expect(api.to('PUT /homework/h1/scores').single.body, {
      'rows': [
        {
          'student_id': 's1',
          'raw_score': 8,
          'feedback': 'Good',
          'is_missing': false,
          'ratings': null,
        },
      ],
    });
    expect(find.textContaining('8/10'), findsOneWidget);
  });

  testWidgets('mark a written answer in a test', (tester) async {
    final api = _school();
    final c = await _signedIn(tester, api);
    await _go(tester, c, '/grading');
    await tester.tap(find.byKey(const Key('grading-e1')));
    await tester.pumpAndSettle();
    expect(find.byType(GradingDetailScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('submission-sub1')));
    await tester.pumpAndSettle();
    expect(find.text('Because of axioms.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('marks-q2')), '5');
    await tester.pump();
    await _tap(tester, find.byKey(const Key('grades-save')));
    expect(api.to('PATCH /exams/grading/e1/submissions/sub1').single.body, {
      'grades': [
        {'question_id': 'q2', 'marks_obtained': 5},
      ],
    });
    expect(find.byType(GradingDetailScreen), findsOneWidget);
  });
}

final _en = AppLocalizationsEn();

const _rina = {'role': 'TEACHER', 'full_name': 'Rina Akter'};
const _slot = '11111111-1111-4111-8111-111111111111';
const _date = '2026-11-18';

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

Future<ProviderContainer> _signedIn(WidgetTester tester, FakeApi api) =>
    pumpInstructorApp(
      tester,
      api: api,
      session: Session.fromPayload({...sessionPayload(), ..._rina}),
      prefs: {'language': 'en'},
    );

Future<void> _go(WidgetTester tester, ProviderContainer c, String route) async {
  c.read(routerProvider).go(route);
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

/// Scrolls the page on top to [f] and taps it.
Future<void> _tap(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      f,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Map<String, Object?> _attendance() => {
  'slot_id': _slot,
  'date': _date,
  'section': {'id': 'sec1', 'name': 'A', 'class_name': 'Class 6'},
  'subject': {'id': 'sub1', 'name': 'Mathematics'},
  'start_time': '10:00',
  'end_time': '10:45',
  'class_type': 'IN_PERSON',
  'mode': 'CHECK_IN',
  'starts_at': '2026-11-18T04:00:00.000Z',
  'late_after': '2026-11-18T04:10:00.000Z',
  'ends_at': '2026-11-18T04:45:00.000Z',
  'state': 'OPEN',
  'closed': null,
  'teacher': {'id': 't1', 'full_name': 'Rina Akter'},
  'counts': {
    'students': 1,
    'present': 0,
    'late': 0,
    'absent': 0,
    'leave': 0,
    'waiting': 1,
    'flagged': 0,
  },
  'cancelled': null,
  'change': null,
  'can_correct': true,
  'can_cancel': false,
  'can_restore': false,
  'can_change': false,
};

Map<String, Object?> _classDay() => {
  ..._attendance(),
  'students': [
    {
      'person': {'id': 's3', 'full_name': 'Sami Rahman', 'roll_no': '3'},
      'role': 'STUDENT',
      'status': 'OPEN',
      'record': null,
      'corrections': <Object>[],
      'can_correct': true,
    },
  ],
  'teachers': <Object>[],
};

Map<String, Object?> _leave() => {
  'id': 'w1',
  'person': {'id': 's9', 'full_name': 'Karim Hasan'},
  'person_type': 'STUDENT',
  'class_name': 'Class 6 A',
  'from_date': '2026-11-20',
  'to_date': '2026-11-21',
  'school_days': 2,
  'reason': 'Fever',
  'file': null,
  'status': 'PENDING',
  'applied_by': {'id': 's9', 'full_name': 'Karim Hasan'},
  'decided_by': null,
  'decided_at': null,
  'decision_note': null,
  'cancelled_by': null,
  'cancelled_at': null,
  'created_at': '2026-11-17T10:00:00.000Z',
  'can_decide': true,
  'can_cancel': false,
};

Map<String, Object?> _hw({String id = 'h1', String status = 'PUBLISHED'}) => {
  'id': id,
  'title': 'Chapter 3 exercise',
  'submission_type': 'FILE',
  'status': status,
  'subject': {'id': 'math', 'name': 'Mathematics'},
  'instructions': null,
  'total_marks': 10,
  'due_at': '2026-11-25T17:59:00.000Z',
  'attachments': <Object>[],
  'can_edit': true,
  'targets': [
    {
      'offering_id': 'o1',
      'section_label': 'Class 6 A',
      'student_ids': <String>[],
    },
  ],
  'student_count': 1,
  'publish_at': null,
};

Map<String, Object?> _grid({bool scored = false}) => {
  'homework': {
    'id': 'h1',
    'total_marks': 10,
    'submission_type': 'FILE',
    'due_at': '2026-11-15T17:59:00.000Z',
    'scores_published_at': null,
  },
  'counts': {
    'students': 1,
    'handed_in': 1,
    'late': 0,
    'missing': 0,
    'scored': scored ? 1 : 0,
  },
  'rows': [
    {
      'student': {'id': 's1', 'full_name': 'Karim Hasan', 'roll_no': '1'},
      'latest': {
        'id': 'sub1',
        'version': 1,
        'submitted_at': '2026-11-14T10:00:00.000Z',
        'is_late': false,
        'late_minutes': null,
        'status': 'SUBMITTED',
      },
      'versions': 1,
      'score': scored
          ? {
              'raw_score': 8,
              'penalty': 0,
              'final_score': 8,
              'total_marks': 10,
              'percent': 80,
              'grade': null,
              'feedback': 'Good',
              'ratings': null,
              'is_missing': false,
            }
          : null,
    },
  ],
};

Map<String, Object?> _gradingSummary() => {
  'exam': {
    'id': 'e1',
    'test_name': 'Algebra final',
    'subject': 'Mathematics',
    'class_name': 'Class 6',
    'total_marks': 10,
    'has_manual_questions': true,
    'grading_status': 'NEEDS_GRADING',
    'is_result_published': false,
    'result_published_at': null,
  },
  'stats': {
    'total_students': 1,
    'submissions': 1,
    'not_submitted': 0,
    'graded': 0,
    'pending': 1,
  },
  'submissions': [
    {
      'submission_id': 'sub1',
      'student_id': 's1',
      'student_name': 'Karim Hasan',
      'email': null,
      'submitted_at': '2026-11-17T04:50:00.000Z',
      'status': 'SUBMITTED',
      'total_score': 4,
      'max_score': 10,
      'is_graded': false,
      'grading_status': 'PENDING',
      'proctoring_summary': {'total_violations': 0},
    },
  ],
};

/// One school as Rina, who teaches Mathematics in Class 6 A.
FakeApi _school() => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /calendar/me', (_) => ok({'items': <Object>[]}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  // Attendance.
  ..on(
    'GET /attendance/sessions',
    (_) => ok({
      'date': _date,
      'today': _date,
      'time_zone': 'Asia/Dhaka',
      'closed': null,
      'sessions': [_attendance()],
    }),
  )
  ..on('GET /attendance/sessions/$_slot/$_date', (_) => ok(_classDay()))
  ..on(
    'PUT /attendance/sessions/$_slot/$_date/records/s3',
    (_) => ok(_classDay()),
  )
  // Leave.
  ..on(
    'GET /attendance/leave/mine',
    (_) => ok({
      'today': _date,
      'can_apply': true,
      'person_type': 'TEACHER',
      'can_apply_for_others': false,
      'can_approve': true,
      'requests': <Object>[],
    }),
  )
  ..on(
    'GET /attendance/leave/approvals',
    (r) => ok(r.query['status'] == 'PENDING' ? [_leave()] : <Object>[]),
  )
  ..on('POST /attendance/leave/w1/approve', (_) => ok(_leave()))
  // Homework.
  ..on('GET /homework', (_) => ok([_hw()]))
  ..on(
    'GET /homework/subject-classes',
    (_) => ok([
      {
        'offering_id': 'o1',
        'session_id': 'se1',
        'section_label': 'Class 6 A',
        'subject': {'id': 'math', 'name': 'Mathematics'},
      },
    ]),
  )
  ..on(
    'GET /offerings/o1/roster',
    (_) => ok([
      {'student_id': 's1', 'full_name': 'Karim Hasan', 'roll_no': '1'},
    ]),
  )
  ..on('POST /homework', (_) => ok(_hw(id: 'h9', status: 'DRAFT')))
  ..on('POST /homework/h9/publish', (_) => ok(_hw(id: 'h9')))
  ..on('GET /homework/h1', (_) => ok(_hw()))
  ..on('GET /homework/h1/grid', (_) => ok(_grid()))
  ..on(
    'GET /homework/h1/submissions/sub1',
    (_) => ok({
      'versions': [
        {
          'id': 'sub1',
          'version': 1,
          'submitted_at': '2026-11-14T10:00:00.000Z',
          'is_late': false,
          'status': 'SUBMITTED',
          'text_answer': 'x = 4',
          'files': <Object>[],
        },
      ],
    }),
  )
  ..on('PUT /homework/h1/scores', (_) => ok(_grid(scored: true)))
  // Marking tests.
  ..on(
    'GET /exams/grading/list',
    (_) => ok([
      {
        'id': 'e1',
        'test_name': 'Algebra final',
        'subject': 'Mathematics',
        'class_name': 'Class 6',
        'exam_end_time': '2026-11-17T05:00:00.000Z',
        'lifecycle_status': 'completed',
        'total_participants': 1,
        'submitted_count': 1,
        'graded_count': 0,
        'pending_count': 1,
        'average_percentage': null,
        'has_manual_questions': true,
        'is_result_published': false,
        'result_published_at': null,
        'grading_status': 'NEEDS_GRADING',
      },
    ]),
  )
  ..on('GET /exams/grading/e1', (_) => ok(_gradingSummary()))
  ..on(
    'GET /exams/grading/e1/submissions/sub1',
    (_) => ok({
      'submission': {
        'submission_id': 'sub1',
        'student_name': 'Karim Hasan',
        'total_score': 0,
        'max_score': 10,
      },
      'totals': {
        'manual_total_count': 1,
        'manual_graded_count': 0,
        'auto_total_count': 0,
        'auto_graded_count': 0,
      },
      'questions': [
        {
          'question_id': 'q2',
          'question': 'Explain a proof.',
          'points': 10,
          'type': 'written',
          'answer': {'type': 'text', 'student_answer': 'Because of axioms.'},
          'is_correct': null,
          'marks_obtained': 0,
        },
      ],
    }),
  )
  ..on(
    'PATCH /exams/grading/e1/submissions/sub1',
    (_) => ok(<String, Object>{}),
  );

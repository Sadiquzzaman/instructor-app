import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/attendance/screens/class_attendance_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

const _slot = '11111111-1111-4111-8111-111111111111';
const _date = '2026-11-18';

Session _teacher() => Session.fromPayload({
  ...sessionPayload(),
  'role': 'TEACHER',
  'full_name': 'Rina Akter',
});

Map<String, Object?> _session({
  bool canCorrect = true,
  bool canCancel = true,
  bool canRestore = false,
  bool canChange = false,
  Map<String, Object?>? cancelled,
  Map<String, Object?>? change,
  Map<String, Object?>? counts,
}) => {
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
  'counts':
      counts ??
      {
        'students': 3,
        'present': 1,
        'late': 1,
        'absent': 0,
        'leave': 0,
        'waiting': 1,
        'flagged': 1,
      },
  'cancelled': cancelled,
  'change': change,
  'can_correct': canCorrect,
  'can_cancel': canCancel,
  'can_restore': canRestore,
  'can_change': canChange,
};

Map<String, Object?> _row(
  String id,
  String name,
  String status, {
  Map<String, Object?>? record,
  List<Object> corrections = const [],
  bool canCorrect = true,
  String? roll,
}) => {
  'person': {'id': id, 'full_name': name, 'roll_no': roll},
  'role': 'STUDENT',
  'status': status,
  'record': record,
  'corrections': corrections,
  'can_correct': canCorrect,
};

Map<String, Object?> _detail({
  Map<String, Object?>? session,
  List<Object>? students,
}) => {
  ...session ?? _session(),
  'students':
      students ??
      [
        _row(
          's1',
          'Karim Hasan',
          'PRESENT',
          roll: '1',
          record: {
            'status': 'PRESENT',
            'checked_in_at': '2026-11-18T04:02:00.000Z',
            'distance_m': 12,
            'accuracy_m': 8,
            'flag': 'EDGE_ACCURACY',
          },
        ),
        _row(
          's2',
          'Nadia Islam',
          'LATE',
          roll: '2',
          record: {'status': 'LATE', 'late_minutes': 7},
          corrections: [
            {
              'id': 'c1',
              'old_status': 'ABSENT',
              'new_status': 'LATE',
              'reason': 'Bus was late',
              'corrected_by': {'id': 't1', 'full_name': 'Rina Akter'},
              'created_at': '2026-11-18T05:00:00.000Z',
            },
          ],
        ),
        _row('s3', 'Sami Rahman', 'OPEN', roll: '3'),
      ],
  'teachers': [_row('t1', 'Rina Akter', 'PRESENT', canCorrect: false)],
};

FakeApi _api({
  List<Object>? sessions,
  FakeHandler? detail,
  FakeHandler? correct,
  FakeHandler? cancel,
  FakeHandler? restore,
}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
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
    'GET /attendance/sessions',
    (r) => ok({
      'date': r.query['date'] ?? _date,
      'today': _date,
      'time_zone': 'Asia/Dhaka',
      'closed': null,
      'sessions': sessions ?? [_session()],
    }),
  )
  ..on('GET /attendance/sessions/$_slot/$_date', detail ?? (_) => ok(_detail()))
  ..on(
    'PUT /attendance/sessions/$_slot/$_date/records/s3',
    correct ?? (_) => ok(_detail()),
  )
  ..on(
    'POST /attendance/sessions/$_slot/$_date/cancel',
    cancel ?? (_) => ok(_detail()),
  )
  ..on(
    'POST /attendance/sessions/$_slot/$_date/restore',
    restore ?? (_) => ok(_detail()),
  );

Future<void> _openList(WidgetTester tester, FakeApi api, {String? lang}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _teacher(),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go('/attendance');
  await tester.pumpAndSettle();
}

Future<void> _openClass(WidgetTester tester, FakeApi api) async {
  await _openList(tester, api);
  await tester.tap(find.byKey(const Key('session-$_slot')));
  await tester.pumpAndSettle();
  expect(find.byType(ClassSessionScreen), findsOneWidget);
}

Finder _scrollable() => find.byType(Scrollable).first;

void main() {
  group('one day changes', changeTests);
  testWidgets('the day: each class with its counts and state', (tester) async {
    final api = _api();
    await _openList(tester, api);
    expect(find.byType(ClassAttendanceScreen), findsOneWidget);
    expect(find.text(_en.classAttendanceTitle), findsOneWidget);
    expect(find.text('Mathematics · Class 6 A'), findsOneWidget);
    expect(find.text(_en.classAttendanceStateOPEN), findsOneWidget);
    expect(find.text(_en.classAttendanceCountPresent(1)), findsOneWidget);
    expect(find.text(_en.classAttendanceCountLate(1)), findsOneWidget);
    expect(find.text(_en.classAttendanceCountAbsent(0)), findsOneWidget);
    expect(find.text(_en.classAttendanceCountWaiting(1)), findsOneWidget);
    expect(find.text(_en.classAttendanceCountFlagged(1)), findsOneWidget);
    expect(find.text(_en.classAttendanceCountLeave(0)), findsNothing);
    expect(find.text(_en.classAttendanceViewAndCorrect), findsOneWidget);
    // Today unless a date is chosen.
    expect(api.to('GET /attendance/sessions').single.query['date'], isNull);
  });

  testWidgets('no classes; cancelled and changed classes say so', (
    tester,
  ) async {
    await _openList(tester, _api(sessions: []));
    expect(find.text(_en.classAttendanceEmpty), findsOneWidget);
  });

  testWidgets('a cancelled, changed class', (tester) async {
    await _openList(
      tester,
      _api(
        sessions: [
          _session(
            canCorrect: false,
            cancelled: {'at': null, 'by': null, 'note': null},
            change: {
              'routine_start_time': '09:00',
              'routine_end_time': '09:45',
              'substitute': null,
              'at': null,
              'by': null,
              'note': null,
            },
          ),
        ],
      ),
    );
    expect(find.text(_en.classAttendanceCancelled), findsOneWidget);
    expect(find.text(_en.classAttendanceChanged), findsOneWidget);
    expect(find.text(_en.classAttendanceView), findsOneWidget);
  });

  testWidgets('a class: everyone with status, check-in, flag and trail', (
    tester,
  ) async {
    await _openClass(tester, _api());
    expect(find.text(_en.classAttendanceStudentsCount(3)), findsOneWidget);
    expect(find.text('1. Karim Hasan'), findsOneWidget);
    expect(
      find.textContaining(_en.classAttendanceDistance(12, 8)),
      findsOneWidget,
    );
    expect(find.text(_en.classAttendanceFlagEDGEACCURACY), findsOneWidget);
    expect(find.textContaining(_en.myAttendanceLateBy(7)), findsOneWidget);
    expect(find.byKey(const Key('trail-c1')), findsOneWidget);
    expect(find.textContaining('Bus was late'), findsOneWidget);
    // Students can be corrected; the teacher's own record cannot.
    expect(find.byKey(const Key('correct-s3')), findsOneWidget);
    expect(find.byKey(const Key('correct-t1')), findsNothing);
  });

  testWidgets('correct: needs a reason, then sends status, reason, minutes', (
    tester,
  ) async {
    final api = _api();
    await _openClass(tester, api);
    await tester.tap(find.byKey(const Key('correct-s3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('correction-save')));
    await tester.pumpAndSettle();
    expect(find.text(_en.classAttendanceReasonRequired), findsOneWidget);
    expect(
      api.to('PUT /attendance/sessions/$_slot/$_date/records/s3'),
      isEmpty,
    );

    await tester.tap(find.byKey(const Key('correction-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.myAttendanceStatusLATE).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('correction-minutes')), '5');
    await tester.enterText(
      find.byKey(const Key('correction-reason')),
      '  Phone had no internet  ',
    );
    await tester.tap(find.byKey(const Key('correction-save')));
    await tester.pumpAndSettle();
    expect(
      api.to('PUT /attendance/sessions/$_slot/$_date/records/s3').single.body,
      {'status': 'LATE', 'reason': 'Phone had no internet', 'late_minutes': 5},
    );
    expect(
      find.text(_en.classAttendanceCorrected('Sami Rahman')),
      findsOneWidget,
    );
  });

  testWidgets('correct: a refusal in the web\'s words', (tester) async {
    await _openClass(
      tester,
      _api(
        correct: (_) => apiError(409, code: 'ATTENDANCE_CORRECTION_TOO_OLD'),
      ),
    );
    await tester.tap(find.byKey(const Key('correct-s3')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('correction-reason')),
      'Was here',
    );
    await tester.tap(find.byKey(const Key('correction-save')));
    await tester.pumpAndSettle();
    expect(
      find.text(_en.classAttendanceErrorsATTENDANCECORRECTIONTOOOLD),
      findsOneWidget,
    );
  });

  testWidgets('cancel the class with a note; then restore it', (tester) async {
    final cancelledDetail = _detail(
      session: _session(
        canCorrect: false,
        canCancel: false,
        canRestore: true,
        cancelled: {
          'at': '2026-11-18T03:00:00.000Z',
          'by': {'id': 't1', 'full_name': 'Rina Akter'},
          'note': 'I am unwell',
        },
      ),
    );
    final api = _api(cancel: (_) => ok(cancelledDetail));
    await _openClass(tester, api);
    await tester.tap(find.byKey(const Key('cancel-class')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('cancel-note')),
      ' I am unwell ',
    );
    await tester.tap(find.byKey(const Key('confirm-cancel')));
    await tester.pumpAndSettle();
    expect(
      api.to('POST /attendance/sessions/$_slot/$_date/cancel').single.body,
      {'note': 'I am unwell'},
    );
    expect(find.byKey(const Key('cancelled-banner')), findsOneWidget);
    expect(
      find.text(_en.classAttendanceCancelledBannerNote('I am unwell')),
      findsOneWidget,
    );
    expect(
      find.text(_en.classAttendanceCancelledToast('Mathematics · Class 6 A')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('restore-class')));
    await tester.pumpAndSettle();
    expect(
      api.to('POST /attendance/sessions/$_slot/$_date/restore'),
      hasLength(1),
    );
    expect(find.byKey(const Key('cancelled-banner')), findsNothing);
    expect(find.byKey(const Key('cancel-class')), findsOneWidget);
  });

  testWidgets('cancel: a refusal shows in the form', (tester) async {
    await _openClass(
      tester,
      _api(cancel: (_) => apiError(409, code: 'ATTENDANCE_CANCEL_ENDED')),
    );
    await tester.tap(find.byKey(const Key('cancel-class')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-cancel')));
    await tester.pumpAndSettle();
    expect(
      find.text(_en.classAttendanceErrorsATTENDANCECANCELENDED),
      findsOneWidget,
    );
  });

  testWidgets('a day\'s change shows; corrections closed say why', (
    tester,
  ) async {
    await _openClass(
      tester,
      _api(
        detail: (_) => ok(
          _detail(
            // A class long over: corrections are past a teacher's limit.
            session: {
              ..._session(
                canCorrect: false,
                canCancel: false,
                change: {
                  'routine_start_time': '09:00',
                  'routine_end_time': '09:45',
                  'substitute': {'id': 't2', 'full_name': 'Jamal Uddin'},
                  'at': '2026-11-17T10:00:00.000Z',
                  'by': {'id': 'o1', 'full_name': 'Owner'},
                  'note': 'Moved after lunch',
                },
              ),
              'state': 'CLOSED',
              'starts_at': '2026-11-01T04:00:00.000Z',
            },
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('change-section')), findsOneWidget);
    expect(
      find.text(_en.classAttendanceChangeSubstituteIs('Jamal Uddin')),
      findsOneWidget,
    );
    expect(find.text(_en.classAttendanceTooOldHint), findsOneWidget);
    expect(find.byKey(const Key('cancel-class')), findsNothing);
  });

  testWidgets('a failure says so; a locked plan says so', (tester) async {
    var calls = 0;
    final api = _api()
      ..on(
        'GET /attendance/sessions',
        (_) => ++calls == 1
            ? apiError(500)
            : apiError(403, code: 'FEATURE_NOT_IN_PLAN', feature: 'attendance'),
      );
    await _openList(tester, api);
    expect(find.text(_en.classAttendanceLoadFailed), findsOneWidget);
    await tester.tap(find.text(_en.uiErrorRetry));
    await tester.pumpAndSettle();
    expect(find.text(_en.featuresLockedTitle), findsOneWidget);
  });

  testWidgets('another date asks for that date', (tester) async {
    final api = _api();
    await _openList(tester, api);
    await tester.tap(find.byKey(const Key('attendance-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('19'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(api.to('GET /attendance/sessions').last.query['date'], '2026-11-19');
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _openList(tester, _api(), lang: 'bn');
    expect(find.text(bn.classAttendanceTitle), findsOneWidget);
    await tester.tap(find.byKey(const Key('session-$_slot')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('person-s3')),
      200,
      scrollable: _scrollable(),
    );
    expect(tester.takeException(), isNull);
  });
}

void changeTests() {
  Map<String, Object?> changeable({Map<String, Object?>? change}) => _detail(
    session: _session(canCorrect: false, canChange: true, change: change),
  );

  testWidgets('change a class for the day: a substitute and a note', (
    tester,
  ) async {
    final api = _api(detail: (_) => ok(changeable()))
      ..on(
        'POST /attendance/sessions/$_slot/$_date/change',
        (_) => ok(
          changeable(
            change: {
              'routine_start_time': '10:00',
              'routine_end_time': '10:45',
              'substitute': {'id': 't2', 'full_name': 'Jamal Uddin'},
              'at': '2026-11-18T02:00:00.000Z',
              'by': {'id': 't1', 'full_name': 'Rina Akter'},
              'note': 'Rina is at a workshop',
            },
          ),
        ),
      );
    await _openClass(tester, api);
    await tester.tap(find.byKey(const Key('change-open')));
    await tester.pumpAndSettle();
    // The routine's teacher is the default; the others can take it.
    expect(
      find.text(_en.classAttendanceChangeRoutineTeacher('Rina Akter')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('change-substitute')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jamal Uddin').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('change-note')),
      ' Rina is at a workshop ',
    );
    await tester.ensureVisible(find.byKey(const Key('change-save')));
    await tester.tap(find.byKey(const Key('change-save')));
    await tester.pumpAndSettle();
    // The times stay the class's own (10:00 in Dhaka).
    expect(
      api.to('POST /attendance/sessions/$_slot/$_date/change').single.body,
      {
        'start_time': '10:00',
        'end_time': '10:45',
        'substitute_teacher_id': 't2',
        'note': 'Rina is at a workshop',
      },
    );
    expect(
      find.text(_en.classAttendanceChangeSubstituteIs('Jamal Uddin')),
      findsOneWidget,
    );
    expect(
      find.text(_en.classAttendanceChangedToast('Mathematics · Class 6 A')),
      findsOneWidget,
    );
  });

  testWidgets('undo a change: the routine times, no substitute', (
    tester,
  ) async {
    final api =
        _api(
          detail: (_) => ok(
            changeable(
              change: {
                'routine_start_time': '09:00',
                'routine_end_time': '09:45',
                'substitute': null,
                'at': null,
                'by': null,
                'note': null,
              },
            ),
          ),
        )..on(
          'POST /attendance/sessions/$_slot/$_date/change',
          (_) => ok(changeable()),
        );
    await _openClass(tester, api);
    await tester.tap(find.byKey(const Key('change-undo')));
    await tester.pumpAndSettle();
    expect(
      api.to('POST /attendance/sessions/$_slot/$_date/change').single.body,
      {
        'start_time': '09:00',
        'end_time': '09:45',
        'substitute_teacher_id': null,
      },
    );
    expect(find.byKey(const Key('change-undo')), findsNothing);
  });

  testWidgets('a change refused: the overlap in the web\'s words', (
    tester,
  ) async {
    await _openClass(
      tester,
      _api(detail: (_) => ok(changeable()))..on(
        'POST /attendance/sessions/$_slot/$_date/change',
        (_) => (
          409,
          {
            'statusCode': 409,
            'error': true,
            'message': 'Overlap',
            'code': 'ATTENDANCE_CHANGE_OVERLAP',
            'details': {'start_time': '10:30', 'end_time': '11:15'},
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('change-open')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('change-save')));
    await tester.tap(find.byKey(const Key('change-save')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        _en.classAttendanceErrorsATTENDANCECHANGEOVERLAP('10:30', '11:15'),
      ),
      findsOneWidget,
    );
  });
}

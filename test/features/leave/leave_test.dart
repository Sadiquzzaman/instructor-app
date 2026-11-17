import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/features/leave/data/leave_repository.dart';
import 'package:instructor_app/features/leave/screens/apply_leave_screen.dart';
import 'package:instructor_app/features/leave/screens/leave_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();
final _today = OrgTime.today();

Map<String, Object?> _request(
  String id, {
  String status = 'PENDING',
  String from = '2026-11-20',
  String to = '2026-11-21',
  bool canCancel = false,
  Map<String, Object?>? decidedBy,
  String? note,
  Map<String, Object?>? file,
}) => {
  'id': id,
  'person': {'id': 'user-1', 'full_name': 'Test Student'},
  'person_type': 'STUDENT',
  'class_name': 'Class 6 A',
  'from_date': from,
  'to_date': to,
  'school_days': 2,
  'reason': 'Fever',
  'file': file,
  'status': status,
  'applied_by': {'id': 'user-1', 'full_name': 'Test Student'},
  'decided_by': decidedBy,
  'decided_at': null,
  'decision_note': note,
  'cancelled_by': null,
  'cancelled_at': null,
  'created_at': '2026-11-17T10:00:00.000Z',
  'can_decide': false,
  'can_cancel': canCancel,
};

FakeApi _api({
  bool canApply = true,
  List<Map<String, Object?>>? requests,
  FakeHandler? apply,
  FakeHandler? mine,
}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /calendar/me', (_) => ok({'items': <Object>[]}))
  ..on(
    'GET /attendance/leave/mine',
    mine ??
        (_) => ok({
          'today': _today,
          'can_apply': canApply,
          'person_type': 'STUDENT',
          'can_apply_for_others': false,
          'can_approve': false,
          'requests':
              requests ??
              [
                _request('r1', canCancel: true),
                _request(
                  'r2',
                  status: 'REJECTED',
                  from: '2026-11-10',
                  to: '2026-11-10',
                  decidedBy: {'id': 't1', 'full_name': 'Rina Akter'},
                  note: 'Exam day',
                  file: {
                    'id': 'f1',
                    'name': 'note.pdf',
                    'mime': 'application/pdf',
                  },
                ),
              ],
        }),
  )
  ..on(
    'POST /attendance/leave/r1/cancel',
    (_) => ok(_request('r1', status: 'CANCELLED')),
  )
  ..on('POST /attendance/leave', apply ?? (r) => ok(_request('new')));

Future<ProviderContainer> _open(
  WidgetTester tester,
  FakeApi api, {
  String? lang,
}) async {
  final c = await pumpInstructorApp(
    tester,
    api: api,
    session: testSession(),
    prefs: {'language': ?lang},
  );
  c.read(routerProvider).go(AppRoutes.leave);
  await tester.pumpAndSettle();
  return c;
}

Future<void> _openForm(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('apply-leave')));
  await tester.pumpAndSettle();
  expect(find.byType(ApplyLeaveScreen), findsOneWidget);
}

/// The first day: the picker opens on today; OK picks it.
Future<void> _pickToday(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('leave-from')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('leave-submit')));
  await tester.tap(find.byKey(const Key('leave-submit')));
  await tester.pumpAndSettle();
}

void main() {
  test('a request reads every part', () {
    final r = LeaveRequest.fromJson(
      _request(
        'x',
        decidedBy: {'id': 't', 'full_name': 'Rina'},
        file: {'id': 'f', 'name': 'a.pdf'},
      ),
    )!;
    expect(r.schoolDays, 2);
    expect(r.decidedBy?.name, 'Rina');
    expect(r.fileId, 'f');
    expect(LeaveRequest.fromJson({'reason': 'x'}), isNull);
  });

  testWidgets('my leave: dates, status, the answer, attachment, withdraw', (
    tester,
  ) async {
    await _open(tester, _api());
    expect(find.byType(LeaveScreen), findsOneWidget);
    expect(find.text(_en.leaveStatusPENDING), findsOneWidget);
    expect(find.text(_en.leaveStatusREJECTED), findsOneWidget);
    expect(
      find.text(_en.leaveDecidedBy('Rina Akter', 'Exam day')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('leave-r2')),
        matching: find.text(_en.leaveAttachment),
      ),
      findsOneWidget,
    );
    // Only the pending one can be withdrawn.
    expect(find.text(_en.leaveWithdraw), findsOneWidget);
  });

  testWidgets('withdraw asks first, then withdraws', (tester) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(find.text(_en.leaveWithdraw));
    await tester.pumpAndSettle();
    expect(find.text(_en.leaveWithdrawTitle), findsOneWidget);
    await tester.tap(find.text(_en.leaveCancel));
    await tester.pumpAndSettle();
    expect(api.to('POST /attendance/leave/r1/cancel'), isEmpty);

    await tester.tap(find.text(_en.leaveWithdraw));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, _en.leaveWithdraw).last);
    await tester.pumpAndSettle();
    expect(api.to('POST /attendance/leave/r1/cancel'), hasLength(1));
    expect(find.text(_en.leaveWithdrawn), findsOneWidget);
  });

  testWidgets('apply: the web\'s checks, then one day with a reason', (
    tester,
  ) async {
    final api = _api(apply: (_) => ok(_request('new', status: 'APPROVED')));
    await _open(tester, api);
    await _openForm(tester);

    await _submit(tester);
    expect(
      find.text(_en.leaveErrorsATTENDANCELEAVEDATESINVALID),
      findsOneWidget,
    );
    await _pickToday(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('leave-reason')),
        matching: find.byType(TextField),
      ),
      'ok',
    );
    await _submit(tester);
    expect(find.text(_en.leaveErrorsREASONREQUIRED), findsOneWidget);
    expect(api.to('POST /attendance/leave'), isEmpty);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('leave-reason')),
        matching: find.byType(TextField),
      ),
      '  Family wedding  ',
    );
    await _submit(tester);
    expect(api.to('POST /attendance/leave').single.body, {
      'from_date': _today,
      'to_date': _today,
      'reason': 'Family wedding',
    });
    expect(find.byType(ApplyLeaveScreen), findsNothing);
    expect(find.text(_en.leaveFormApprovedAtOnce), findsOneWidget);
  });

  testWidgets('an overlapping request says which one', (tester) async {
    final api = _api(
      apply: (_) => (
        409,
        {
          'statusCode': 409,
          'error': true,
          'message': 'Overlaps',
          'code': 'ATTENDANCE_LEAVE_OVERLAP',
          'details': {'from_date': '2026-11-20', 'to_date': '2026-11-21'},
        },
      ),
    );
    await _open(tester, api);
    await _openForm(tester);
    await _pickToday(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('leave-reason')),
        matching: find.byType(TextField),
      ),
      'Fever',
    );
    await _submit(tester);
    expect(
      find.text(_en.leaveErrorsATTENDANCELEAVEOVERLAP('20 Nov', '21 Nov')),
      findsOneWidget,
    );
    expect(find.byType(ApplyLeaveScreen), findsOneWidget);
  });

  testWidgets('cannot apply: no button; nothing yet', (tester) async {
    await _open(tester, _api(canApply: false, requests: []));
    expect(find.byKey(const Key('apply-leave')), findsNothing);
    expect(find.text(_en.leaveEmptyMine), findsOneWidget);
  });

  testWidgets('a failed load can be retried', (tester) async {
    var calls = 0;
    await _open(
      tester,
      _api(
        mine: (_) => calls++ == 0
            ? apiError(500)
            : ok({'today': _today, 'can_apply': true, 'requests': <Object>[]}),
      ),
    );
    expect(find.text(_en.leaveLoadFailed), findsOneWidget);
    await tester.tap(find.text(_en.uiErrorRetry));
    await tester.pumpAndSettle();
    expect(find.text(_en.leaveEmptyMine), findsOneWidget);
  });

  testWidgets('in Bangla', (tester) async {
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.leaveApply), findsOneWidget);
    expect(find.text(bn.leaveStatusPENDING), findsOneWidget);
  });
}

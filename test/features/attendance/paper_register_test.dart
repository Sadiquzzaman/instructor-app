import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/features/attendance/screens/paper_register_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();
final _month = OrgTime.today().substring(0, 7);

Session _teacher() =>
    Session.fromPayload({...sessionPayload(), 'role': 'TEACHER'});

Map<String, Object?> _register({
  String mode = 'PAPER_REGISTER',
  bool canImport = true,
  bool noClasses = false,
}) => {
  'section': {'id': 'sec2', 'name': 'B', 'class_name': 'Class 7'},
  'month': _month,
  'today': '$_month-18',
  'mode': mode,
  'can_import': canImport,
  'classes': noClasses
      ? <Object>[]
      : [
          {
            'header': '$_month-16',
            'date': '$_month-16',
            'start_time': '10:00',
            'end_time': '10:45',
            'slot_id': 'sl1',
          },
          {
            'header': '$_month-17',
            'date': '$_month-17',
            'start_time': '10:00',
            'end_time': '10:45',
            'slot_id': 'sl1',
          },
        ],
  'students': [
    {
      'id': 's1',
      'full_name': 'Karim Hasan',
      'roll_no': '1',
      'marks': ['PRESENT', null],
    },
    {
      'id': 's2',
      'full_name': 'Nadia Islam',
      'roll_no': '2',
      'marks': [null, null],
    },
  ],
};

Map<String, Object?> _check({
  bool valid = true,
  int newMarks = 1,
  int changed = 0,
  int checkIns = 0,
  List<Object> rows = const [],
}) => {
  'section': {'id': 'sec2', 'name': 'B', 'class_name': 'Class 7'},
  'month': _month,
  'valid': valid,
  'columns': <Object>[],
  'rows': rows,
  'summary': {
    'new': newMarks,
    'changed': changed,
    'unchanged': 1,
    'kept': 0,
    'check_ins': checkIns,
  },
};

FakeApi _api({
  FakeHandler? register,
  FakeHandler? preview,
  FakeHandler? import,
}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /attendance/register/sections',
    (_) => ok([
      {
        'id': 'sec2',
        'name': 'B',
        'class_name': 'Class 7',
        'mode': 'PAPER_REGISTER',
      },
    ]),
  )
  ..on(
    'GET /attendance/register/sections/sec2',
    register ?? (_) => ok(_register()),
  )
  ..on(
    'POST /attendance/register/sections/sec2/preview',
    preview ?? (_) => ok(_check()),
  )
  ..on(
    'POST /attendance/register/sections/sec2/import',
    import ?? (_) => ok(_check()),
  );

Future<void> _open(WidgetTester tester, FakeApi api, {String? lang}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _teacher(),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go('/attendance-register');
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('register-save')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('register-save')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the month\'s grid; tapping a cell cycles its mark', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    expect(find.byType(PaperRegisterScreen), findsOneWidget);
    expect(api.to('GET /attendance/register/sections/sec2').single.query, {
      'month': _month,
    });
    expect(find.byKey(const Key('register-grid')), findsOneWidget);
    expect(find.text('Karim Hasan'), findsOneWidget);
    // Nothing changed yet: Save waits.
    final save = find.byKey(const Key('register-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    // Empty → P → L.
    await tester.tap(find.byKey(const Key('cell-s2-0')));
    await tester.tap(find.byKey(const Key('cell-s2-0')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('cell-s2-0')),
        matching: find.text(_en.myAttendanceLetterLATE),
      ),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
  });

  testWidgets('save: checks, then imports the whole month as the CSV would', (
    tester,
  ) async {
    final api = _api(import: (_) => ok(_check(newMarks: 1)));
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('cell-s2-0')));
    await tester.pump();
    await _save(tester);
    final body = {
      'month': _month,
      'header': ['roll_no', 'name', '$_month-16', '$_month-17'],
      'rows': [
        {
          'cells': ['1', 'Karim Hasan', 'P', ''],
        },
        {
          'cells': ['2', 'Nadia Islam', 'P', ''],
        },
      ],
    };
    expect(
      api.to('POST /attendance/register/sections/sec2/preview').single.body,
      body,
    );
    expect(
      api.to('POST /attendance/register/sections/sec2/import').single.body,
      body,
    );
    expect(find.text(_en.registerImported(1, 0)), findsOneWidget);
    // The register is loaded again with the saved marks.
    expect(api.to('GET /attendance/register/sections/sec2'), hasLength(2));
  });

  testWidgets('problems show on their cell; nothing is imported', (
    tester,
  ) async {
    final api = _api(
      preview: (_) => ok(
        _check(
          valid: false,
          rows: [
            {
              'row': 2,
              'roll_no': '2',
              'name': 'Nadia Islam',
              'student': null,
              'marks': 1,
              'issues': <String>[],
              'notes': <String>[],
              'cells': [
                {
                  'column': 2,
                  'value': 'P',
                  'status': 'PRESENT',
                  'old_status': null,
                  'change': null,
                  'issues': ['NOT_JOINED'],
                  'notes': <String>[],
                },
              ],
            },
          ],
        ),
      ),
    );
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('cell-s2-0')));
    await tester.pump();
    await _save(tester);
    expect(api.to('POST /attendance/register/sections/sec2/import'), isEmpty);
    expect(find.text(_en.registerImporterPreviewProblems), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('cell-s2-0')),
        matching: find.byType(Tooltip),
      ),
      findsOneWidget,
    );
    final tip = tester.widget<Tooltip>(
      find.descendant(
        of: find.byKey(const Key('cell-s2-0')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tip.message, _en.registerImporterIssuesNOTJOINED);
  });

  testWidgets(
    'self check-ins the grid disagrees with: asked first, replaced only when ticked',
    (tester) async {
      final api = _api(
        preview: (_) => ok(_check(newMarks: 0, checkIns: 1)),
        import: (_) => ok(_check(newMarks: 0, changed: 1)),
      );
      await _open(tester, api);
      await tester.tap(find.byKey(const Key('cell-s1-0')));
      await tester.pump();
      await _save(tester);
      // First Save: the choice, nothing imported.
      expect(api.to('POST /attendance/register/sections/sec2/import'), isEmpty);
      expect(find.text(_en.registerImporterPreviewReady), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('register-replace-check-ins')),
      );
      await tester.tap(find.byKey(const Key('register-replace-check-ins')));
      await tester.pump();
      await _save(tester);
      expect(
        api.to('POST /attendance/register/sections/sec2/import').single.body,
        containsPair('overwrite_check_ins', true),
      );
      expect(find.text(_en.registerImported(0, 1)), findsOneWidget);
    },
  );

  testWidgets('kept check-ins and nothing else: nothing to import', (
    tester,
  ) async {
    final api = _api(preview: (_) => ok(_check(newMarks: 0, checkIns: 1)));
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('cell-s1-0')));
    await tester.pump();
    await _save(tester);
    await _save(tester);
    expect(api.to('POST /attendance/register/sections/sec2/import'), isEmpty);
    expect(find.text(_en.registerImporterNothingToChange), findsOneWidget);
  });

  testWidgets('a refusal in the web\'s words', (tester) async {
    await _open(
      tester,
      _api(import: (_) => apiError(409, code: 'ATTENDANCE_REGISTER_CHANGED')),
    );
    await tester.tap(find.byKey(const Key('cell-s2-0')));
    await tester.pump();
    await _save(tester);
    expect(
      find.text(_en.registerErrorsATTENDANCEREGISTERCHANGED),
      findsOneWidget,
    );
  });

  testWidgets('a self check-in section is read-only', (tester) async {
    await _open(
      tester,
      _api(
        register: (_) => ok(_register(mode: 'SELF_CHECKIN', canImport: false)),
      ),
    );
    expect(find.byKey(const Key('register-grid')), findsOneWidget);
    expect(find.byKey(const Key('register-save')), findsNothing);
    await tester.tap(find.byKey(const Key('cell-s2-0')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('cell-s2-0')),
        matching: find.text('·'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a month with no class days; months move', (tester) async {
    final api = _api(register: (_) => ok(_register(noClasses: true)));
    await _open(tester, api);
    expect(find.text(_en.registerNoClasses), findsOneWidget);
    await tester.tap(find.byKey(const Key('register-next')));
    await tester.pumpAndSettle();
    expect(
      api.to('GET /attendance/register/sections/sec2').last.query['month'],
      isNot(_month),
    );
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.registerTitle), findsOneWidget);
    expect(find.byKey(const Key('register-grid')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

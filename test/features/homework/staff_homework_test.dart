import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/homework/screens/staff_homework_screens.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Session _teacher() =>
    Session.fromPayload({...sessionPayload(), 'role': 'TEACHER'});

Map<String, Object?> _hw({
  String id = 'h1',
  String status = 'DRAFT',
  String? html = '<p>Read chapter 3.</p><ul><li>Q1</li></ul>',
  List<Object>? targets,
  List<Object>? attachments,
}) => {
  'id': id,
  'title': 'Chapter 3 exercise',
  'submission_type': 'FILE',
  'status': status,
  'subject': {'id': 'math', 'name': 'Mathematics'},
  'instructions': html == null ? null : {'html': html},
  'total_marks': 10,
  'due_at': '2026-11-25T17:59:00.000Z',
  'attachments': attachments ?? <Object>[],
  'can_edit': true,
  'targets':
      targets ??
      [
        {
          'offering_id': 'o1',
          'section_label': 'Class 6 A',
          'student_ids': <String>[],
        },
      ],
  'student_count': 30,
  'publish_at': null,
};

FakeApi _api({FakeHandler? save, FakeHandler? detail}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /homework',
    (r) => ok(
      r.query['status'] == 'CANCELLED'
          ? <Object>[]
          : [_hw(), _hw(id: 'h2', status: 'PUBLISHED')],
    ),
  )
  ..on(
    'GET /homework/subject-classes',
    (_) => ok([
      {
        'offering_id': 'o1',
        'session_id': 'se1',
        'section_label': 'Class 6 A',
        'subject': {'id': 'math', 'name': 'Mathematics'},
      },
      {
        'offering_id': 'o2',
        'session_id': 'se1',
        'section_label': 'Class 6 B',
        'subject': {'id': 'math', 'name': 'Mathematics'},
      },
      {
        'offering_id': 'o3',
        'session_id': 'se1',
        'section_label': 'Class 6 A',
        'subject': {'id': 'eng', 'name': 'English'},
      },
    ]),
  )
  ..on(
    'GET /offerings/o1/roster',
    (_) => ok([
      {'student_id': 's1', 'full_name': 'Karim Hasan', 'roll_no': '1'},
      {'student_id': 's2', 'full_name': 'Nadia Islam', 'roll_no': '2'},
    ]),
  )
  ..on('POST /homework', save ?? (_) => ok(_hw(id: 'h9')))
  ..on('PATCH /homework/h1', save ?? (_) => ok(_hw()))
  ..on(
    'POST /homework/h9/publish',
    (_) => ok(_hw(id: 'h9', status: 'PUBLISHED')),
  )
  ..on('POST /homework/h1/publish', (_) => ok(_hw(status: 'PUBLISHED')))
  ..on('POST /homework/h1/cancel', (_) => ok(_hw(status: 'CANCELLED')))
  ..on('GET /homework/h1', detail ?? (_) => ok(_hw()))
  ..on('GET /homework/h1/submissions', (_) => ok(<Object>[]));

Future<void> _open(
  WidgetTester tester,
  FakeApi api,
  String route, {
  String? lang,
}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _teacher(),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go(route);
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

Finder _scrollable() => find.byType(Scrollable).first;

Finder _editorScrollable() => find
    .descendant(
      of: find.byType(HomeworkEditorScreen),
      matching: find.byType(Scrollable),
    )
    .first;

/// Scrolls the editor to [key] (up when [up]).
Future<void> _showEditor(
  WidgetTester tester,
  String key, {
  bool up = false,
}) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    up ? -200 : 200,
    scrollable: _editorScrollable(),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapEditor(WidgetTester tester, String key) async {
  await _showEditor(tester, key);
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the list: status, subject, classes, due, students; filter', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, '/homework');
    expect(find.byType(StaffHomeworkListScreen), findsOneWidget);
    expect(api.to('GET /homework').single.query['status'], 'ACTIVE');
    expect(find.text(_en.homeworkStatusesDRAFT), findsOneWidget);
    expect(find.text(_en.homeworkStatusesPUBLISHED), findsOneWidget);
    expect(find.text('Mathematics · Class 6 A'), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('homework-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.homeworkFiltersCANCELLED).last);
    await tester.pumpAndSettle();
    expect(api.to('GET /homework').last.query['status'], 'CANCELLED');
    expect(find.text(_en.homeworkStaffEmpty), findsOneWidget);
  });

  testWidgets('new homework: checks, one subject, some students, publish', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, '/homework');
    await tester.tap(find.byKey(const Key('homework-new')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeworkEditorScreen), findsOneWidget);

    // A title, then a class, are needed.
    await _tapEditor(tester, 'editor-publish');
    expect(find.text(_en.homeworkErrorsTITLEREQUIRED), findsOneWidget);
    await _showEditor(tester, 'editor-title', up: true);
    await tester.enterText(find.byKey(const Key('editor-title')), ' Ch 3 ');
    await _tapEditor(tester, 'editor-publish');
    expect(find.text(_en.homeworkErrorsCLASSREQUIRED), findsOneWidget);

    await _showEditor(tester, 'offering-o1', up: true);
    await tester.tap(find.byKey(const Key('offering-o1')));
    await tester.pumpAndSettle();
    // Another subject is greyed out once one is picked.
    final english = tester.widget<CheckboxListTile>(
      find.byKey(const Key('offering-o3')),
    );
    expect(english.onChanged, isNull);

    await _tapEditor(tester, 'editor-some-students');
    await _tapEditor(tester, 'student-s2');
    await _showEditor(tester, 'editor-instructions');
    await tester.enterText(
      find.byKey(const Key('editor-instructions')),
      'Read chapter 3.\n\n- Question 1\n- Question 2',
    );
    await _showEditor(tester, 'editor-marks');
    await tester.enterText(find.byKey(const Key('editor-marks')), '10');
    await _tapEditor(tester, 'type-TEXT');
    await _tapEditor(tester, 'editor-publish');

    expect(api.to('POST /homework').single.body, {
      'title': 'Ch 3',
      'instructions': {
        'html': '<p>Read chapter 3.</p><ul><li>Question 1</li><li>Question 2</li></ul>',
      },
      'total_marks': 10,
      'due_at': null,
      'attachment_ids': <String>[],
      'submission_type': 'TEXT',
      'offering_ids': ['o1'],
      'student_ids': ['s2'],
    });
    expect(api.to('POST /homework/h9/publish'), hasLength(1));
    expect(find.text(_en.homeworkPublished), findsOneWidget);
  });

  testWidgets('a homework: facts, instructions; publish now; withdraw', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, '/homework/h1');
    expect(find.byType(StaffHomeworkDetailScreen), findsOneWidget);
    expect(find.text('Chapter 3 exercise'), findsOneWidget);
    expect(find.text('Read chapter 3.\n• Q1'), findsOneWidget);
    expect(find.text('Class 6 A'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);

    await tester.tap(find.byKey(const Key('homework-publish')));
    await tester.pumpAndSettle();
    expect(api.to('POST /homework/h1/publish').single.body, <String, Object>{});
    expect(find.text(_en.homeworkStatusesPUBLISHED), findsOneWidget);
    expect(find.byKey(const Key('homework-publish')), findsNothing);
    // Let the message go before reaching for Withdraw.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('homework-withdraw')),
      200,
      scrollable: _scrollable(),
    );
    await tester.tap(find.byKey(const Key('homework-withdraw')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('withdraw-confirm')));
    await tester.pumpAndSettle();
    expect(api.to('POST /homework/h1/cancel'), hasLength(1));
    expect(find.text(_en.homeworkWithdrawn), findsOneWidget);
  });

  testWidgets('edit: the form is filled; a published one keeps its classes', (
    tester,
  ) async {
    final api = _api(
      detail: (_) => ok(
        _hw(
          status: 'PUBLISHED',
          html: '<p>Use <strong>pen</strong>.</p>',
          attachments: [
            {'id': 'f1', 'name': 'sheet.pdf', 'mime': 'application/pdf'},
          ],
        ),
      ),
    );
    await _open(tester, api, '/homework/h1');
    await tester.tap(find.byKey(const Key('homework-edit')));
    await tester.pumpAndSettle();
    expect(find.text(_en.homeworkEditorPublishedHint), findsOneWidget);
    // Formatting from the website: the words stay, with a note.
    expect(find.text('Use pen.'), findsOneWidget);
    expect(find.text(_en.appHomeworkPlainText), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('offering-o2')))
          .onChanged,
      isNull,
    );
    expect(find.byKey(const Key('editor-draft')), findsNothing);
    await tester.enterText(find.byKey(const Key('editor-title')), 'Chapter 3');
    await _tapEditor(tester, 'editor-publish');
    final body = api.to('PATCH /homework/h1').single.body! as Map;
    expect(body['title'], 'Chapter 3');
    expect(body['attachment_ids'], ['f1']);
    // The due time kept, in Dhaka time.
    expect(body['due_at'], '2026-11-25T17:59:00.000Z');
    expect(body.containsKey('offering_ids'), isFalse);
    expect(body.containsKey('submission_type'), isFalse);
  });

  testWidgets('a refusal in the web\'s words', (tester) async {
    await _open(
      tester,
      _api(save: (_) => apiError(400, code: 'HOMEWORK_SESSION_CLOSED')),
      '/homework/h1',
    );
    await tester.tap(find.byKey(const Key('homework-edit')));
    await tester.pumpAndSettle();
    await _tapEditor(tester, 'editor-draft');
    expect(find.text(_en.homeworkErrorsHOMEWORKSESSIONCLOSED), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), '/homework', lang: 'bn');
    expect(find.text(bn.homeworkNew), findsOneWidget);
    await tester.tap(find.byKey(const Key('homework-new')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

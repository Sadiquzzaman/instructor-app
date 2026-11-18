import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/results/screens/paper_exam_screens.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Session _teacher() =>
    Session.fromPayload({...sessionPayload(), 'role': 'TEACHER'});

Map<String, Object?> _exam({
  List<Object>? parts,
  bool published = false,
  bool canEdit = true,
}) => {
  'id': 'x1',
  'name': 'Half-yearly',
  'exam_date': '2026-11-10',
  'total_marks': 100,
  'parts': parts,
  'session_id': 'se1',
  'term': {'id': 't1', 'name': 'Term 1'},
  'offering': {
    'id': 'o1',
    'subject': {'id': 'm', 'name': 'Mathematics'},
    'section': {'id': 'sa', 'name': 'A', 'class_name': 'Class 6'},
  },
  'published_at': published ? '2026-11-12T04:00:00.000Z' : null,
  'counts': {'students': 2, 'entered': 1},
  'can_edit': canEdit,
};

Map<String, Object?> _grid({List<Object>? parts, bool canEdit = true}) => {
  'exam': _exam(parts: parts, canEdit: canEdit),
  'rows': [
    {
      'student': {'id': 's1', 'full_name': 'Karim Hasan', 'roll_no': '1'},
      'marks': 72,
      'part_marks': parts == null ? null : {'MCQ': 30, 'Written': 42},
      'is_absent': false,
      'percent': 72,
      'grade': {'grade': 'A', 'gpa': 4},
    },
    {
      'student': {'id': 's2', 'full_name': 'Nadia Islam', 'roll_no': '2'},
      'marks': null,
      'part_marks': null,
      'is_absent': false,
      'percent': null,
      'grade': null,
    },
  ],
};

FakeApi _api({FakeHandler? grid, FakeHandler? save, FakeHandler? create}) =>
    FakeApi()
      ..on('GET /auth/contexts', (_) => ok(<Object>[]))
      ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
      ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
      ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
      ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
      ..on('GET /offline-exams', (_) => ok([_exam()]))
      ..on(
        'GET /offline-exams/subject-classes',
        (_) => ok([
          {
            'offering_id': 'o1',
            'session_id': 'se1',
            'section_label': 'Class 6 A',
            'subject': {'id': 'm', 'name': 'Mathematics'},
            'terms': [
              {
                'id': 't1',
                'name': 'Term 1',
                'start_date': null,
                'end_date': null,
              },
            ],
          },
        ]),
      )
      ..on('POST /offline-exams', create ?? (_) => ok(_exam()))
      ..on('GET /offline-exams/x1/marks', grid ?? (_) => ok(_grid()))
      ..on('PUT /offline-exams/x1/marks', save ?? (_) => ok(_grid()))
      ..on('POST /offline-exams/x1/publish', (_) => ok(<String, Object>{}))
      ..on('DELETE /offline-exams/x1', (_) => ok(<String, Object>{}));

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

void main() {
  testWidgets('the list: paper exams with marks entered; one opens', (
    tester,
  ) async {
    await _open(tester, _api(), '/marks');
    expect(find.byType(StaffMarksScreen), findsOneWidget);
    expect(find.text('Half-yearly'), findsOneWidget);
    expect(find.text(_en.marksEntered(1, 2)), findsOneWidget);
    expect(find.text(_en.marksNotPublished), findsOneWidget);
    await tester.tap(find.byKey(const Key('paper-x1')));
    await tester.pumpAndSettle();
    expect(find.byType(PaperMarksScreen), findsOneWidget);
  });

  testWidgets('add a paper exam with parts and a term', (tester) async {
    final api = _api();
    await _open(tester, api, '/marks');
    await tester.tap(find.byKey(const Key('paper-add')));
    await tester.pumpAndSettle();
    // A class is needed first.
    await tester.tap(find.byKey(const Key('paper-save')));
    await tester.pumpAndSettle();
    expect(find.text(_en.marksErrorsCLASSREQUIRED), findsOneWidget);

    await tester.tap(find.byKey(const Key('paper-class')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mathematics · Class 6 A').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('paper-name')),
      ' Half-yearly ',
    );
    await tester.tap(find.byKey(const Key('paper-term')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Term 1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('paper-with-parts')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('part-marks-0')), '30');
    await tester.enterText(find.byKey(const Key('part-marks-1')), '70');
    await tester.pump();
    expect(find.text(_en.marksPartsSum(100, 100)), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('paper-save')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(PaperExamFormScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const Key('paper-save')));
    await tester.pumpAndSettle();
    final body = api.to('POST /offline-exams').single.body! as Map;
    expect(body['offering_id'], 'o1');
    expect(body['name'], 'Half-yearly');
    expect(body['total_marks'], 100);
    expect(body['term_id'], 't1');
    expect(body['parts'], [
      {'name': _en.marksPartMcq, 'marks': 30},
      {'name': _en.marksPartWritten, 'marks': 70},
    ]);
    expect(find.text(_en.marksCreatedHint('Half-yearly')), findsOneWidget);
  });

  testWidgets('marks: enter, mark absent, save only the changed lines', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, '/marks/x1');
    expect(find.text('72/100 (A)'), findsOneWidget);
    final save = find.byKey(const Key('marks-save'));
    await tester.scrollUntilVisible(save, 200, scrollable: _scrollable());
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.scrollUntilVisible(
      find.byKey(const Key('mark-s2-marks')),
      -200,
      scrollable: _scrollable(),
    );
    await tester.enterText(find.byKey(const Key('mark-s2-marks')), '120');
    await tester.pump();
    expect(find.text('0–100'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('mark-s2-marks')), '64.5');
    await tester.pump();
    expect(find.text(_en.marksUnsaved(1)), findsOneWidget);
    await tester.scrollUntilVisible(save, 200, scrollable: _scrollable());
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(api.to('PUT /offline-exams/x1/marks').single.body, {
      'rows': [
        {'student_id': 's2', 'marks': 64.5, 'is_absent': false},
      ],
    });

    await tester.scrollUntilVisible(
      find.byKey(const Key('absent-s1')),
      -200,
      scrollable: _scrollable(),
    );
    await tester.tap(find.byKey(const Key('absent-s1')));
    await tester.pump();
    await tester.scrollUntilVisible(save, 200, scrollable: _scrollable());
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(api.to('PUT /offline-exams/x1/marks').last.body, {
      'rows': [
        {'student_id': 's1', 'is_absent': true},
      ],
    });
  });

  testWidgets('an exam with parts: marks per part', (tester) async {
    final parts = [
      {'name': 'MCQ', 'marks': 30},
      {'name': 'Written', 'marks': 70},
    ];
    final api = _api(grid: (_) => ok(_grid(parts: parts)));
    await _open(tester, api, '/marks/x1');
    await tester.scrollUntilVisible(
      find.byKey(const Key('mark-s2-Written')),
      200,
      scrollable: _scrollable(),
    );
    await tester.enterText(find.byKey(const Key('mark-s2-MCQ')), '25');
    await tester.enterText(find.byKey(const Key('mark-s2-Written')), '40');
    await tester.pump();
    final save = find.byKey(const Key('marks-save'));
    await tester.scrollUntilVisible(save, 200, scrollable: _scrollable());
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(api.to('PUT /offline-exams/x1/marks').single.body, {
      'rows': [
        {
          'student_id': 's2',
          'part_marks': {'MCQ': 25, 'Written': 40},
          'is_absent': false,
        },
      ],
    });
  });

  testWidgets('a refusal names the student', (tester) async {
    await _open(
      tester,
      _api(
        save: (_) => (
          400,
          {
            'statusCode': 400,
            'error': true,
            'message': 'Bad',
            'code': 'OFFLINE_EXAM_MARKS_INVALID',
            'details': {'index': 0},
          },
        ),
      ),
      '/marks/x1',
    );
    await tester.enterText(find.byKey(const Key('mark-s2-marks')), '50');
    await tester.pump();
    final save = find.byKey(const Key('marks-save'));
    await tester.scrollUntilVisible(save, 200, scrollable: _scrollable());
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
      find.text(
        _en.marksErrorFor(
          'Nadia Islam',
          _en.marksErrorsOFFLINEEXAMMARKSINVALID,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('publish and delete after asking', (tester) async {
    final api = _api();
    await _open(tester, api, '/marks/x1');
    await tester.tap(find.byKey(const Key('paper-publish')));
    await tester.pumpAndSettle();
    expect(find.text(_en.marksPublishDetail(1)), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm')));
    await tester.pumpAndSettle();
    expect(api.to('POST /offline-exams/x1/publish'), hasLength(1));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('paper-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm')));
    await tester.pumpAndSettle();
    expect(api.to('DELETE /offline-exams/x1'), hasLength(1));
    expect(find.byType(StaffMarksScreen), findsOneWidget);
  });

  testWidgets('not theirs to change: read-only', (tester) async {
    await _open(
      tester,
      _api(grid: (_) => ok(_grid(canEdit: false))),
      '/marks/x1',
    );
    expect(find.text(_en.marksReadOnly), findsOneWidget);
    expect(find.byKey(const Key('marks-save')), findsNothing);
    expect(find.byKey(const Key('paper-publish')), findsNothing);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), '/marks/x1', lang: 'bn');
    expect(find.text(bn.marksPublish), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

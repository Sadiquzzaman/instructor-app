import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/files/file_picking.dart';
import 'package:instructor_app/core/files/local_file.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/text/html_text.dart';
import 'package:instructor_app/features/homework/data/homework.dart';
import 'package:instructor_app/features/homework/homework_text.dart';
import 'package:instructor_app/features/homework/screens/homework_detail_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Map<String, Object?> _homework(
  String id, {
  String type = 'TEXT',
  String? due,
  int? handedIn,
  List<Map<String, Object?>> attachments = const [],
}) => {
  'id': id,
  'title': 'Chapter 3 exercises',
  'instructions': {'html': '<p>Do <b>1–5</b>.</p><ul><li>Show work</li></ul>'},
  'submission_type': type,
  'total_marks': 10,
  'due_at':
      due ??
      DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String(),
  'status': 'PUBLISHED',
  'subject': {'id': 's', 'name': 'English'},
  'targets': <Object>[],
  'attachments': attachments,
  'student_count': 0,
  'can_edit': false,
  'my_submission': handedIn == null
      ? null
      : {
          'version': handedIn,
          'submitted_at': '2026-11-17T10:00:00Z',
          'is_late': false,
          'status': 'SUBMITTED',
        },
};

Map<String, Object?> _mine({
  bool canSubmit = true,
  String? blockedBy,
  List<Map<String, Object?>> submissions = const [],
  Map<String, Object?>? score,
}) => {
  'submissions': submissions,
  'can_submit': canSubmit,
  'blocked_by': blockedBy,
  'submissions_left': 2,
  'late_now': false,
  'max_files': 5,
  'score': score,
};

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

FakeApi _api({
  Map<String, Object?>? homework,
  FakeHandler? mine,
  FakeHandler? submit,
}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /calendar/me', (_) => ok({'items': <Object>[]}))
  ..on(
    'GET /homework/mine',
    (_) => ok([_homework('h1'), _homework('h2', handedIn: 2)]),
  )
  ..on('GET /homework/h1', (_) => ok(homework ?? _homework('h1')))
  ..on('GET /homework/gone', (_) => apiError(404, code: 'HOMEWORK_NOT_FOUND'))
  ..on('GET /homework/h1/my-submissions', mine ?? (_) => ok(_mine()))
  ..on('POST /homework/h1/submissions', submit ?? (_) => ok(_mine()))
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
  );

Future<ProviderContainer> _open(
  WidgetTester tester,
  FakeApi api,
  String route, {
  String? lang,
}) async {
  final c = await pumpInstructorApp(
    tester,
    api: api,
    session: testSession(),
    prefs: {'language': ?lang},
    overrides: [filePickingProvider.overrideWithValue(_Picking())],
  );
  c.read(routerProvider).go(route);
  await tester.pumpAndSettle();
  return c;
}

Finder _scrollable() => find
    .descendant(
      of: find.byType(HomeworkDetailScreen),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: _scrollable());
  await tester.pumpAndSettle();
}

void main() {
  test('the web editor\'s HTML as plain text', () {
    expect(
      htmlToText(
        '<p>Do <b>1–5</b> &amp; check.</p><ul><li>One</li><li>Two</li></ul><p></p><p>End<br>here</p>',
      ),
      'Do 1–5 & check.\n• One\n• Two\n\nEnd\nhere',
    );
    expect(htmlToText(''), '');
  });

  test('due states and the score line', () {
    final now = DateTime.utc(2026, 11, 18, 10);
    expect(dueStateOf(null, now), 'none');
    expect(dueStateOf(DateTime.utc(2026, 11, 18, 9), now), 'overdue');
    expect(dueStateOf(DateTime.utc(2026, 11, 18, 20), now), 'soon');
    expect(dueStateOf(DateTime.utc(2026, 11, 21), now), 'later');
    expect(
      scoreText(
        const HomeworkScore(
          finalScore: 8,
          totalMarks: 10,
          percent: 80,
          grade: 'A',
        ),
        'en',
      ),
      '8/10 · 80% (A)',
    );
    expect(scoreText(const HomeworkScore(), 'en'), isNull);
    expect(AppRoutes.isAppPage('/homework/abc'), isTrue);
    expect(AppRoutes.isAppPage('/homework/abc/similarity'), isFalse);
  });

  testWidgets('the list: handed in, or when it is due; opens the page', (
    tester,
  ) async {
    await _open(tester, _api(), AppRoutes.homework);
    expect(find.text(_en.homeworkHandedIn(2)), findsOneWidget);
    expect(find.textContaining('Due'), findsWidgets);
    await tester.tap(find.byKey(const Key('homework-h1')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeworkDetailScreen), findsOneWidget);
    expect(find.text('Do 1–5.\n• Show work'), findsOneWidget);
  });

  testWidgets('hand in a typed answer with a photo', (tester) async {
    var reads = 0;
    final api = _api(
      mine: (_) => ok(
        reads++ == 0
            ? _mine()
            : _mine(
                submissions: [
                  {
                    'id': 's1',
                    'version': 1,
                    'text_answer': 'My answer',
                    'submitted_at': '2026-11-18T05:00:00Z',
                    'is_late': false,
                    'late_minutes': null,
                    'status': 'SUBMITTED',
                    'files': [
                      {'id': 'f1', 'name': 'page.jpg', 'mime': 'image/jpeg'},
                    ],
                  },
                ],
              ),
      ),
    );
    await _open(tester, api, '${AppRoutes.homework}/h1');
    await _scrollTo(tester, find.byKey(const Key('homework-submit')));
    await tester.tap(find.byKey(const Key('homework-submit')));
    await tester.pumpAndSettle();
    expect(
      find.text(_en.homeworkErrorsHOMEWORKSUBMISSIONEMPTY),
      findsOneWidget,
    );

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('homework-answer')),
        matching: find.byType(TextField),
      ),
      '  My answer  ',
    );
    await _scrollTo(tester, find.byKey(const Key('attach')));
    await tester.tap(find.byKey(const Key('attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.appAttachChoosePhotos));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('homework-submit')));
    await tester.tap(find.byKey(const Key('homework-submit')));
    await tester.pumpAndSettle();
    expect(api.to('POST /homework/h1/submissions').single.body, {
      'file_ids': ['f1'],
      'text_answer': 'My answer',
    });
    await _scrollTo(tester, find.byKey(const Key('version-1')));
    expect(find.text(_en.homeworkMyWorkVersion(1)), findsOneWidget);
    expect(find.text('My answer'), findsOneWidget);
  });

  testWidgets('late hand-ins not allowed: says why, no form', (tester) async {
    await _open(
      tester,
      _api(
        homework: _homework('h1', type: 'FILE'),
        mine: (_) =>
            ok(_mine(canSubmit: false, blockedBy: 'HOMEWORK_LATE_NOT_ALLOWED')),
      ),
      '${AppRoutes.homework}/h1',
    );
    await _scrollTo(tester, find.byKey(const Key('my-work')));
    expect(find.text(_en.homeworkErrorsHOMEWORKLATENOTALLOWED), findsOneWidget);
    expect(find.byKey(const Key('homework-submit')), findsNothing);
  });

  testWidgets('paper homework: handed to the teacher; the score shows', (
    tester,
  ) async {
    await _open(
      tester,
      _api(
        homework: _homework(
          'h1',
          type: 'PAPER',
          attachments: [
            {
              'id': 'a1',
              'name': 'sheet.pdf',
              'mime': 'application/pdf',
              'url': '/files/a1/content',
            },
          ],
        ),
        mine: (_) => ok(
          _mine(
            canSubmit: false,
            blockedBy: 'HOMEWORK_PAPER_NO_SUBMISSION',
            score: {
              'raw_score': 9,
              'penalty': 1,
              'final_score': 8,
              'total_marks': 10,
              'percent': 80,
              'grade': {'grade': 'A', 'gpa': 4},
              'feedback': 'Neat work',
              'ratings': {'neatness': 5},
              'is_missing': false,
            },
          ),
        ),
      ),
      '${AppRoutes.homework}/h1',
    );
    expect(find.text('sheet.pdf'), findsOneWidget);
    await _scrollTo(tester, find.byKey(const Key('homework-score')));
    expect(find.text(_en.homeworkMyWorkPaper), findsOneWidget);
    expect(find.text('8/10 · 80% (A)'), findsOneWidget);
    expect(find.text(_en.homeworkMyWorkPenalty(9, 1)), findsOneWidget);
    expect(find.text('Neat work'), findsOneWidget);
    expect(
      find.text(
        _en.homeworkMyWorkRating(_en.homeworkSubmissionsRatingsNeatness, 5),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('homework-submit')), findsNothing);
  });

  testWidgets('a homework that is gone says so', (tester) async {
    await _open(tester, _api(), '${AppRoutes.homework}/gone');
    expect(find.text(_en.homeworkNotFound), findsOneWidget);
    // The failed load leaves a short clean-up timer; let it run out.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('teachers are sent to the website for now', (tester) async {
    final p = sessionPayload();
    final c = await pumpInstructorApp(
      tester,
      api: _api(),
      session: Session.fromPayload({...p, 'role': 'TEACHER'}),
    );
    c.read(routerProvider).go(AppRoutes.homework);
    await tester.pumpAndSettle();
    expect(find.text(_en.appNotYetBody), findsOneWidget);
  });

  testWidgets('in Bangla', (tester) async {
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), AppRoutes.homework, lang: 'bn');
    expect(find.text(bn.homeworkTitle), findsWidgets);
    expect(find.text(bn.homeworkHandedIn(2)), findsOneWidget);
  });
}

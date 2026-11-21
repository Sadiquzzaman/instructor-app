import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/tests/data/exam_to_draft.dart';
import 'package:instructor_app/features/tests/screens/create_test_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Session _teacher() {
  final p = sessionPayload();
  return Session.fromPayload({
    ...p,
    'id': 'me',
    'role': 'TEACHER',
    'organization': <String, dynamic>{
      ...(p['organization'] as Map<String, dynamic>),
      'role': 'TEACHER',
    },
  });
}

/// A test as `GET /exams/:id` returns it to its teacher.
Map<String, Object?> _exam({
  String text = '<p>What is 2 + 2?</p>',
  String audience = 'selected_class',
  String category = 'academic',
  Map<String, Object?>? extra,
}) => {
  'id': 'e1',
  'test_name': 'Algebra',
  'exam_category': category,
  'formState': {
    'testName': 'Algebra',
    'duration': 40,
    'passingScore': 2,
    'allowNegativeMarking': true,
    'negativeMarking': 25,
    'isModelTest': false,
    'allowScreenShare': false,
    'examCategory': category,
    'proctoring': {
      'level': 'LIGHT',
      'checks_off': ['tab_switch'],
      'auto_disqualify': false,
      'disqualify_threshold': 3,
      'disqualify_checks': null,
      'alert_flags': null,
    },
  },
  'publishState': {
    'publishTiming': 'later',
    'scheduleAt': '2026-12-01T04:00:00.000Z',
    'endingAt': '2026-12-01T05:00:00.000Z',
    'testAudience': audience,
    'selectedClassId': 'c6',
    'selectedOfferingId': '',
    'excluded_students': ['s9'],
  },
  'subjects': [
    {
      'id': 'm',
      'name': 'Mathematics',
      'code': 'M',
      'questions': [
        {
          'id': 'q2',
          'type': 'graded',
          'subType': 'matching-ordering',
          'text': '<p>Match</p>',
          'instruction': null,
          'image': null,
          'points': 2,
          'sortOrder': 0,
          'matchingOptions': {
            'left': [
              {'id': 'l1', 'text': 'Dhaka'},
              {'id': 'l2', 'text': 'Paris'},
            ],
            'right': [
              {'id': 'r2', 'text': 'France'},
              {'id': 'r1', 'text': 'Bangladesh'},
            ],
          },
          'answer': {
            'type': 'matchingOrdering',
            'value': ['l1::r1', 'l2::r2'],
          },
        },
        {
          'id': 'q1',
          'type': 'graded',
          'subType': 'multiple-choice',
          'text': text,
          'instruction': 'Pick one',
          'image': 'https://cdn.test/q1.jpg',
          'points': 1,
          'sortOrder': 1,
          'options': [
            {'id': 'o1', 'text': '3', 'image': null},
            {'id': 'o2', 'text': '4', 'image': null},
            {'id': 'o3', 'text': '5', 'image': null},
          ],
          'answer': {
            'type': 'optionId',
            'value': ['o2'],
          },
        },
        {
          'id': 'p1',
          'type': 'passage-question',
          'passageText': '<p>Rivers &amp; hills</p>',
          'instructionLanguage': 'en',
          'sortOrder': 2,
          'childQuestions': [
            {
              'id': 'c1',
              'type': 'passage-question',
              'subType': 'essay',
              'text': '<p>Explain</p>',
              'points': 5,
            },
          ],
        },
        ...?extra == null ? null : [extra],
      ],
    },
  ],
};

FakeApi _api(Map<String, Object?> exam, {FakeHandler? put}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /classes',
    (_) => ok([
      {'id': 'c6', 'class_name': 'Class 6'},
    ]),
  )
  ..on(
    'GET /sections',
    (_) => ok([
      {'id': 'sa', 'name': 'A', 'class_id': 'c6'},
    ]),
  )
  ..on(
    'GET /offerings',
    (_) => ok([
      {
        'id': 'oa',
        'section_id': 'sa',
        'subject': {'id': 'm', 'name': 'Mathematics'},
        'teachers': [
          {'id': 'me', 'full_name': 'Rina'},
        ],
      },
    ]),
  )
  ..on(
    'GET /classes/c6/subjects/assigned',
    (_) => ok([
      {'subject_id': 'm', 'name': 'Mathematics', 'code': 'M'},
    ]),
  )
  ..on(
    'GET /exams/proctoring-options',
    (_) => ok({
      'levels': [
        {'level': 'OFF', 'available': true},
        {'level': 'LIGHT', 'available': true},
      ],
      'default_level': 'LIGHT',
    }),
  )
  ..on('GET /exams/e1', (_) => ok(exam))
  ..on('PUT /exams/e1', put ?? (_) => ok({'id': 'e1'}))
  ..on('GET /exams', (_) => ok(<Object>[]));

Future<void> _open(WidgetTester tester, FakeApi api, {List<Uri>? links}) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _teacher(),
    openedLinks: links,
  );
  app.read(routerProvider).go('/tests/e1/edit');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

void main() {
  group('the simple HTML the app can edit', () {
    test('paragraphs, line breaks and the usual entities', () {
      expect(
        htmlToPlain('<p>a &lt; b <br> c</p><p>next &amp; more</p>'),
        'a < b \n c\n\nnext & more',
      );
      expect(htmlToPlain('plain words'), 'plain words');
      expect(htmlToPlain(null), '');
    });

    test('anything more stays on the web', () {
      for (final html in [
        '<p><strong>bold</strong></p>',
        '<p class="x">styled</p>',
        '<ul><li>list</li></ul>',
        '<span data-type="math">x^2</span>',
        '<p>&times;</p>',
        '<table><tr><td>1</td></tr></table>',
      ]) {
        expect(htmlToPlain(html), isNull, reason: html);
      }
    });
  });

  group('a saved test as a draft', () {
    test('everything the app edits comes back', () {
      final d = draftFromExam(_exam())!;
      expect(d.name, 'Algebra');
      expect(d.duration, '40');
      expect(d.passingScore, '2');
      expect(d.negative, isTrue);
      expect(d.negativePercent, '25');
      expect(d.proctoringLevel, 'LIGHT');
      expect(d.classId, 'c6');
      expect(d.offeringId, isNull);
      expect(d.excluded, ['s9']);
      expect(d.publishNow, isFalse);
      expect(d.scheduleAt, DateTime.utc(2026, 12, 1, 4));
      expect(d.order, ['q2', 'q1', 'p1']);
      final qs = d.subject!.questions;
      final mc = qs.firstWhere((q) => q.id == 'q1');
      expect(mc.text, 'What is 2 + 2?');
      expect(mc.instruction, 'Pick one');
      expect(mc.image, 'https://cdn.test/q1.jpg');
      expect(mc.answer, ['o2']);
      // The right side is put in the answer's order.
      final m = qs.firstWhere((q) => q.id == 'q2');
      expect([for (final o in m.right) o.id], ['r1', 'r2']);
      final p = qs.firstWhere((q) => q.id == 'p1');
      expect(p.isPassage, isTrue);
      expect(p.text, 'Rivers & hills');
      expect(p.language, 'en');
      expect(p.children.single.subType, 'essay');
    });

    test('saved again, it says the same', () {
      final d = draftFromExam(_exam())!;
      final body = d.toBody(DateTime.utc(2026, 11, 21));
      final form = body['formState']! as Map;
      expect(form['negativeMarking'], 25);
      // The settings the app doesn't edit go back as they were.
      expect(form['proctoring'], {
        'level': 'LIGHT',
        'checks_off': ['tab_switch'],
        'auto_disqualify': false,
        'disqualify_threshold': 3,
      });
      expect(form.containsKey('allowScreenShare'), isFalse);
      final publish = body['publishState']! as Map;
      expect(publish['publishTiming'], 'later');
      expect(publish['scheduleAt'], '2026-12-01T04:00:00.000Z');
      expect(publish['endingAt'], '2026-12-01T05:00:00.000Z');
      expect(publish['excluded_students'], ['s9']);
      expect(body['questionOrder'], ['q2', 'q1', 'p1']);
      final qs =
          ((body['subjects']! as List).single as Map)['questions'] as List;
      final m = qs.first as Map;
      expect(m['answer'], {
        'type': 'matchingOrdering',
        'value': ['l1::r1', 'l2::r2'],
      });
      expect((qs[1] as Map)['text'], '<p>What is 2 + 2?</p>');
      expect((qs[2] as Map)['passageText'], '<p>Rivers &amp; hills</p>');
    });

    test('formatting, IELTS, chosen students or media stay on the web', () {
      expect(draftFromExam(_exam(text: '<p><em>Why</em>?</p>')), isNull);
      expect(draftFromExam(_exam(category: 'ielts')), isNull);
      expect(draftFromExam(_exam(audience: 'specific_students')), isNull);
      expect(
        draftFromExam(
          _exam(
            extra: {
              'id': 'p2',
              'type': 'passage-question',
              'passageText': '<p>Listen</p>',
              'audioUrl': 'https://cdn.test/a.mp3',
              'childQuestions': <Object>[],
            },
          ),
        ),
        isNull,
      );
      expect(
        draftFromExam(
          _exam(
            extra: {
              'id': 'q9',
              'type': 'graded',
              'subType': 'answer-box',
              'text': '<p>Old</p>',
            },
          ),
        ),
        isNull,
      );
    });
  });

  testWidgets('edit and save: PUT with the same test', (tester) async {
    final api = _api(_exam());
    await _open(tester, api);
    expect(find.byType(CreateTestScreen), findsOneWidget);
    expect(find.text('Algebra'), findsWidgets);
    expect(find.text(_en.createTestFooterSave), findsNothing);

    for (var i = 0; i < 4; i++) {
      final next = find.byKey(const Key('create-next'));
      await tester.ensureVisible(next);
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
    }
    final save = find.byKey(const Key('create-publish'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    expect(find.text(_en.createTestFooterSave), findsOneWidget);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final body = api.to('PUT /exams/e1').single.body! as Map;
    expect(api.to('POST /exams'), isEmpty);
    expect(body['questionOrder'], ['q2', 'q1', 'p1']);
    expect((body['publishState'] as Map)['publishTiming'], 'later');
  });

  testWidgets('a test with formatting opens the website', (tester) async {
    final links = <Uri>[];
    await _open(
      tester,
      _api(_exam(text: '<p><strong>Bold</strong></p>')),
      links: links,
    );
    expect(find.byKey(const Key('edit-on-website')), findsOneWidget);
    expect(find.text(_en.appTestEditOnWebsiteBody), findsOneWidget);
    await tester.tap(find.text(_en.appTestEditOnWebsite));
    await tester.pumpAndSettle();
    expect(links.single.path, '/tests/create');
    expect(links.single.queryParameters['examId'], 'e1');
  });
}

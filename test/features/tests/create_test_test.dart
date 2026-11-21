import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/tests/data/test_draft.dart';
import 'package:instructor_app/features/tests/screens/create_test_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
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

FakeApi _api({FakeHandler? create}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /classes',
    (_) => ok([
      {'id': 'c6', 'class_name': 'Class 6'},
      {'id': 'c7', 'class_name': 'Class 7'},
    ]),
  )
  ..on(
    'GET /sections',
    (_) => ok([
      {'id': 'sa', 'name': 'A', 'class_id': 'c6'},
      {'id': 'sb', 'name': 'A', 'class_id': 'c7'},
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
      {
        'id': 'ob',
        'section_id': 'sb',
        'subject': {'id': 'm', 'name': 'Mathematics'},
        'teachers': <Object>[],
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
        {'level': 'STRICT', 'available': false},
      ],
      'default_level': 'LIGHT',
    }),
  )
  ..on('POST /exams', create ?? (_) => ok({'id': 'e9'}))
  ..on('GET /exams/e9', (_) => ok({'id': 'e9', 'test_name': 'Algebra'}))
  ..on('GET /exams', (_) => ok(<Object>[]));

Future<void> _open(WidgetTester tester, FakeApi api, {String? lang}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _teacher(),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go('/tests/create');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

Finder _page() => find
    .descendant(
      of: find.byType(CreateTestScreen),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: _page());
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, Finder f, String v) async {
  await tester.scrollUntilVisible(f, 200, scrollable: _page());
  await tester.ensureVisible(f);
  await tester.enterText(f, v);
  await tester.pumpAndSettle();
}

Future<void> _basics(WidgetTester tester) async {
  await _type(tester, find.byKey(const Key('create-name')), 'Algebra');
  await tester.tap(find.byKey(const Key('create-class')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Class 6').last);
  await tester.pumpAndSettle();
  await _type(tester, find.byKey(const Key('create-duration')), '40');
}

Future<void> _question(WidgetTester tester) async {
  await _tap(tester, find.byKey(const Key('create-add-question')));
  await _type(
    tester,
    find
        .byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.key as ValueKey?)?.value.toString().startsWith(
                    'question-text-',
                  ) ==
                  true,
        )
        .first,
    'What is 2 + 2?',
  );
  final options = find.byWidgetPredicate(
    (w) =>
        w is TextField &&
        (w.key as ValueKey?)?.value.toString().startsWith('option-text-') ==
            true,
  );
  for (final (i, v) in ['3', '4', '5'].indexed) {
    await _type(tester, options.at(i), v);
  }
  final correct = find.byWidgetPredicate(
    (w) =>
        w is Checkbox &&
        (w.key as ValueKey?)?.value.toString().startsWith('option-correct-') ==
            true,
  );
  await _tap(tester, correct.at(1));
}

void main() {
  group('the wizard body', () {
    test('plain text becomes simple HTML, escaped', () {
      expect(
        plainToHtml(' a < b \n c\n\nnext '),
        '<p>a &lt; b <br> c</p><p>next</p>',
      );
    });

    test('ids are UUID v4', () {
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(newId()),
        isTrue,
      );
    });

    test('problems: text, points, options, one correct', () {
      final q = DraftQuestion.multipleChoice();
      expect(
        questionProblems(q),
        containsAll(['title', 'optionEmpty:1', 'pickOne']),
      );
      final ok = q.copyWith(
        text: 'Q',
        options: [for (final o in q.options) o.copyWith(text: 'x')],
        answer: [q.options.first.id],
      );
      expect(questionProblems(ok), isEmpty);
      expect(questionProblems(ok.copyWith(points: 0)), ['points']);
    });

    test('a draft survives being written and read', () {
      final d = TestDraft(
        name: 'T',
        classId: 'c6',
        subjects: [
          DraftSubject(
            id: 'm',
            name: 'Maths',
            questions: [DraftQuestion.multipleChoice()],
          ),
        ],
      );
      final back = TestDraft.fromJson(d.toJson());
      expect(back.toJson(), d.toJson());
    });
  });

  testWidgets('make a test: basics, a question, publish now', (tester) async {
    final api = _api();
    await _open(tester, api);
    await _basics(tester);
    // The class has one subject: chosen for them.
    expect(find.text('Mathematics (M)'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('create-next')));
    await _question(tester);
    await _tap(tester, find.byKey(const Key('create-next')));
    expect(find.text('Class 6'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('create-publish')));

    final body = api.to('POST /exams').single.body! as Map;
    expect(body['formState'], {
      'testName': 'Algebra',
      'examCategory': 'academic',
      'duration': 40,
      'isModelTest': false,
      'allowNegativeMarking': false,
    });
    final subjects = body['subjects'] as List;
    expect((subjects.single as Map)['id'], 'm');
    final q = ((subjects.single as Map)['questions'] as List).single as Map;
    expect(q['type'], 'graded');
    expect(q['subType'], 'multiple-choice');
    expect(q['text'], '<p>What is 2 + 2?</p>');
    final second = (q['options'] as List)[1] as Map;
    expect(q['answer'], {
      'type': 'optionId',
      'value': [second['id']],
    });
    expect(body['questionOrder'], [q['id']]);
    final publish = body['publishState'] as Map;
    expect(publish['testAudience'], 'selected_class');
    expect(publish['publishTiming'], 'immediately');
    expect(publish['selectedClassId'], 'c6');
  });

  testWidgets('the web\'s checks stop each step', (tester) async {
    await _open(tester, _api());
    await _tap(tester, find.byKey(const Key('create-next')));
    expect(find.text(_en.createTestToastNameRequired), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _basics(tester);
    await _tap(tester, find.byKey(const Key('create-next')));
    await _tap(tester, find.byKey(const Key('create-next')));
    expect(find.text(_en.createTestToastQuestionRequired), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('create-add-question')));
    await _tap(tester, find.byKey(const Key('create-next')));
    expect(find.text(_en.createTestToastFixQuestions), findsOneWidget);
    expect(find.text(_en.createTestValidationPickOneCorrect), findsOneWidget);
  });

  testWidgets('classes are the ones they teach', (tester) async {
    await _open(tester, _api());
    await tester.tap(find.byKey(const Key('create-class')));
    await tester.pumpAndSettle();
    expect(find.text('Class 7'), findsNothing);
  });

  testWidgets('the draft is kept on the device and comes back', (tester) async {
    final api = _api();
    final app = await pumpInstructorApp(tester, api: api, session: _teacher());
    app.read(routerProvider).go('/tests/create');
    await tester.pumpAndSettle();
    await tester.pump(Duration.zero);
    await tester.pumpAndSettle();
    await _type(tester, find.byKey(const Key('create-name')), 'Kept');
    final saved = app.read(testDraftStoreProvider).load();
    expect(saved?.name, 'Kept');

    // Leave and come back: still there.
    app.read(routerProvider).go('/tests');
    await tester.pumpAndSettle();
    app.read(routerProvider).go('/tests/create');
    await tester.pumpAndSettle();
    expect(find.text('Kept'), findsOneWidget);

    // Cancel clears it.
    await _tap(tester, find.byKey(const Key('create-cancel')));
    expect(app.read(testDraftStoreProvider).load(), isNull);
  });

  testWidgets('a refusal is shown and the draft is kept', (tester) async {
    final api = _api(create: (_) => apiError(403, code: 'PLAN_LIMIT_REACHED'));
    await _open(tester, api);
    await _basics(tester);
    await _tap(tester, find.byKey(const Key('create-next')));
    await _question(tester);
    await _tap(tester, find.byKey(const Key('create-next')));
    await _tap(tester, find.byKey(const Key('create-publish')));
    expect(find.byType(CreateTestScreen), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.createTestTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

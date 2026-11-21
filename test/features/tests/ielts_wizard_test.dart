import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/tests/data/test_draft.dart';
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

FakeApi _api() => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /classes',
    (_) => ok([
      {'id': 'c6', 'class_name': 'Batch 1'},
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
        'subject': {'id': 'm', 'name': 'English'},
        'teachers': [
          {'id': 'me', 'full_name': 'Rina'},
        ],
      },
    ]),
  )
  ..on(
    'GET /classes/c6/subjects/assigned',
    (_) => ok([
      {'subject_id': 'm', 'name': 'English', 'code': 'E'},
    ]),
  )
  ..on('GET /exams/proctoring-options', (_) => ok({'levels': <Object>[]}))
  ..on('POST /exams', (_) => ok({'id': 'e9'}))
  ..on('GET /exams/e9', (_) => ok({'id': 'e9', 'test_name': 'Mock'}))
  ..on('GET /exams', (_) => ok(<Object>[]));

void main() {
  group('IELTS types in the wizard', () {
    test('the server names IELTS true/false true-false-not-given', () {
      final q = DraftQuestion.create('true-false-not-given', type: 'ielts');
      expect([for (final o in q.options) o.text], trueFalseOptions);
      final y = DraftQuestion.create('yes-no-not-given', type: 'ielts');
      expect([for (final o in y.options) o.text], yesNoOptions);
      expect(questionProblems(y.copyWith(text: 'Q')), ['pickOne']);
    });

    test('completion types answer in words; tasks are marked by hand', () {
      final c = DraftQuestion.create(
        'summary-completion',
        type: 'ielts',
      ).copyWith(text: 'S', answer: ['honey', '']);
      expect(c.toBody()['answer'], {
        'type': 'text',
        'value': ['honey', ''],
      });
      expect(questionProblems(c.copyWith(answer: ['', ''])), ['answer']);
      final w = DraftQuestion.create(
        'writing-task-2',
        type: 'ielts',
      ).copyWith(text: 'Discuss.');
      final body = w.toBody();
      expect(body['type'], 'ielts');
      expect(body.containsKey('answer'), isFalse);
      expect(body['wordLimit'], 150);
      final s = DraftQuestion.create(
        'speaking-part-2',
        type: 'ielts',
      ).copyWith(text: 'Talk.');
      expect(s.toBody()['timeLimitSeconds'], 120);
    });

    test('an IELTS test sends its category and modules', () {
      final d = TestDraft(
        name: 'Mock',
        duration: '60',
        examCategory: 'ielts',
        classId: 'c6',
        subjects: [
          DraftSubject(
            id: 'ielts.reading',
            name: 'Reading',
            questions: [DraftQuestion.create('short-answer', type: 'ielts')],
          ),
        ],
      );
      final body = d.toBody(DateTime.utc(2026, 11, 21));
      expect((body['formState']! as Map)['examCategory'], 'ielts');
      final subject = (body['subjects']! as List).single as Map;
      expect(subject['id'], 'ielts.reading');
      expect(subject['moduleKey'], 'ielts.reading');
    });
  });

  testWidgets('choose IELTS: modules, then IELTS questions', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = await pumpInstructorApp(
      tester,
      api: _api(),
      session: _teacher(),
    );
    app.read(routerProvider).go('/tests/create');
    await tester.pumpAndSettle();
    await tester.pump(Duration.zero);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('create-name')), 'Mock');
    await tester.tap(find.byKey(const Key('create-class')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batch 1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.createTestCategoriesIelts));
    await tester.pumpAndSettle();
    // Reading is chosen; the subject list and model test go.
    expect(find.byKey(const Key('create-subject')), findsNothing);
    expect(find.byKey(const Key('create-model-test')), findsNothing);
    await tester.tap(find.byKey(const Key('create-module-ielts.writing')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('create-duration')), '60');
    await tester.pumpAndSettle();
    final next = find.byKey(const Key('create-next'));
    await tester.ensureVisible(next);
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();

    // The modules are the subjects; IELTS is the question category.
    expect(
      find.byKey(const Key('create-subject-tab-ielts.reading')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('create-subject-tab-ielts.writing')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('create-subject-add')), findsNothing);
    expect(find.byKey(const Key('create-category-ielts')), findsOneWidget);
    expect(find.byKey(const Key('create-category-graded')), findsNothing);
    final add = find.byKey(const Key('create-add-question'));
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text(_en.createTestTypesIeltsMultipleChoice), findsOneWidget);
  });
}

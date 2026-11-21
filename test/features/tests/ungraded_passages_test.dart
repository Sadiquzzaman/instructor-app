import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/features/shell/data/entitlements.dart';
import 'package:instructor_app/features/tests/data/test_draft.dart';
import 'package:instructor_app/features/tests/screens/passage_editor.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

DraftQuestion _mc(String type) {
  final q = DraftQuestion.create('multiple-choice', type: type);
  return q.copyWith(
    text: 'Q',
    options: [for (final o in q.options) o.copyWith(text: 'x')],
    answer: [q.options.first.id],
  );
}

/// The passage card alone, with each change kept in the returned list.
Future<List<DraftQuestion>> _edit(
  WidgetTester tester,
  DraftQuestion start,
) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final seen = <DraftQuestion>[start];
  final container = await pumpInstructorApp(
    tester,
    api: FakeApi(),
    session: testSession(),
    overrides: [
      entitlementsProvider.overrideWith(
        (ref) async => const Entitlements(features: {}, limits: {}),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: inLanguage(
        StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: PassageEditor(
              number: 2,
              passage: seen.last,
              onChanged: (q) => setState(() => seen.add(q)),
              onDelete: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return seen;
}

void main() {
  group('ungraded', () {
    test('no options and no answer: the teacher marks it', () {
      for (final t in ungradedTypes) {
        final q = DraftQuestion.create(t, type: 'ungraded');
        expect(q.options, isEmpty, reason: t);
        final body = q.copyWith(text: 'Why?').toBody();
        expect(body['type'], 'ungraded');
        expect(body['subType'], t);
        expect(body.containsKey('answer'), isFalse, reason: t);
        expect(body.containsKey('options'), isFalse, reason: t);
      }
    });

    test('only the text and points are checked', () {
      final q = DraftQuestion.create('true-false', type: 'ungraded');
      expect(questionProblems(q), ['title']);
      expect(questionProblems(q.copyWith(text: 'Is it?')), isEmpty);
    });

    test('changing type stays without options', () {
      final q = DraftQuestion.create('essay', type: 'ungraded');
      expect(q.withSubType('true-false').options, isEmpty);
    });
  });

  group('passages', () {
    test('a new passage has one multiple-choice question', () {
      final p = DraftQuestion.passage();
      expect(p.isPassage, isTrue);
      expect(p.language, 'bn');
      expect(p.children.single.type, passageType);
      expect(p.children.single.subType, 'multiple-choice');
      expect(p.children.single.options, hasLength(minVariableOptions));
    });

    test('sent as the web does, with its questions', () {
      final essay = DraftQuestion.create(
        'essay',
        type: passageType,
      ).copyWith(text: 'Explain', points: 5);
      final p = DraftQuestion.passage().copyWith(
        text: 'Once upon a time',
        language: 'en',
        children: [_mc(passageType), essay],
      );
      final body = p.toBody();
      expect(body['type'], passageType);
      expect(body['passageText'], '<p>Once upon a time</p>');
      expect(body['instructionLanguage'], 'en');
      expect(body.containsKey('subType'), isFalse);
      final kids = body['childQuestions']! as List;
      expect((kids[0] as Map)['answer'], isNotNull);
      expect((kids[1] as Map)['subType'], 'essay');
      expect((kids[1] as Map).containsKey('answer'), isFalse);
      expect(p.marks, 6);
    });

    test('problems: the text, and any question under it', () {
      final p = DraftQuestion.passage();
      expect(questionProblems(p), ['passage', 'children']);
      final ok = p.copyWith(text: 'P', children: [_mc(passageType)]);
      expect(questionProblems(ok), isEmpty);
    });

    test('true/false under a passage still needs its answer', () {
      final q = DraftQuestion.create(
        'true-false',
        type: passageType,
      ).copyWith(text: 'T');
      expect(q.options, hasLength(3));
      expect(questionProblems(q), ['pickOne']);
    });

    test('counts and marks include each question in a passage', () {
      final s = DraftSubject(
        id: 'm',
        name: 'M',
        questions: [
          _mc('graded'),
          DraftQuestion.passage().copyWith(
            children: [_mc(passageType), _mc(passageType)],
          ),
        ],
      );
      expect(s.questionCount, 3);
      expect(s.totalMarks, 3);
    });

    test('a passage survives being written and read', () {
      final p = DraftQuestion.passage().copyWith(text: 'P', language: 'en');
      expect(DraftQuestion.fromJson(p.toJson()).toJson(), p.toJson());
    });

    test('duplicating gives new ids and keeps the right answers', () {
      final q = _mc('graded');
      final copy = q.duplicate();
      expect(copy.id, isNot(q.id));
      expect(copy.options.first.id, isNot(q.options.first.id));
      expect(copy.answer, [copy.options.first.id]);
      expect(questionProblems(copy), isEmpty);
      final p = DraftQuestion.passage().duplicate();
      expect(p.children.single.id, isNot(isEmpty));
    });

    testWidgets('write the passage, pick its language, add questions', (
      tester,
    ) async {
      final seen = await _edit(tester, DraftQuestion.passage());
      final p = seen.last;
      expect(find.text(_en.createTestValidationPassageMissing), findsOneWidget);
      expect(find.text('2.1.'), findsOneWidget);

      // Its only question can't be removed.
      final child = p.children.single;
      expect(
        tester
            .widget<IconButton>(find.byKey(Key('question-delete-${child.id}')))
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byKey(Key('passage-text-${p.id}')),
        'Rivers of Bangladesh',
      );
      await tester.pumpAndSettle();
      expect(find.text(_en.createTestValidationPassageMissing), findsNothing);

      await tester.tap(find.text(_en.createTestPassageEnglish));
      await tester.pumpAndSettle();
      expect(seen.last.language, 'en');

      await tester.tap(find.byKey(Key('passage-add-${p.id}')));
      await tester.pumpAndSettle();
      expect(seen.last.children, hasLength(2));
      expect(find.text('2.2.'), findsOneWidget);
      expect(seen.last.text, 'Rivers of Bangladesh');
    });
  });
}

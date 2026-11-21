import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/features/shell/data/entitlements.dart';
import 'package:instructor_app/features/tests/data/test_draft.dart';
import 'package:instructor_app/features/tests/screens/question_editor.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

/// The editor alone, with each change kept in the returned list.
Future<List<DraftQuestion>> _edit(
  WidgetTester tester,
  DraftQuestion start, {
  double width = 800,
}) async {
  tester.view.physicalSize = Size(width, 1600);
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
            child: QuestionEditor(
              number: 1,
              question: seen.last,
              onChanged: (q) => setState(() => seen.add(q)),
              onDelete: () {},
              onDuplicate: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return seen;
}

Finder _keyed(String prefix) => find.byWidgetPredicate(
  (w) =>
      w is TextField &&
      (w.key as ValueKey?)?.value.toString().startsWith(prefix) == true,
);

void main() {
  group('fill in the blanks', () {
    test('starts with an empty answer and needs one', () {
      final q = DraftQuestion.create('fill-in-the-blanks');
      expect(q.options, isEmpty);
      expect(questionProblems(q), containsAll(['title', 'answer']));
      final done = q.copyWith(
        text: 'Dhaka is the ______ of Bangladesh.',
        answer: ['capital', ''],
      );
      expect(questionProblems(done), isEmpty);
    });

    test('sends the answer and alternative as text', () {
      final q = DraftQuestion.create('fill-in-the-blanks')
          .copyWith(text: 'x', answer: [' capital ', ' Capital ']);
      final body = q.toBody();
      expect(body['answer'], {
        'type': 'text',
        'value': ['capital', 'Capital'],
      });
      expect(body.containsKey('options'), isFalse);
      // No answer: no alternative either (the web's rule).
      expect(q.copyWith(answer: ['', 'Capital']).toBody()['answer'], {
        'type': 'text',
        'value': ['', ''],
      });
    });

    testWidgets('the alternative waits for the answer', (tester) async {
      final seen = await _edit(
        tester,
        DraftQuestion.create('fill-in-the-blanks'),
      );
      expect(find.text(_en.createTestPromptsBlank), findsOneWidget);
      TextField alt() => tester.widget(_keyed('blank-alternative-'));
      expect(alt().enabled, isFalse);
      await tester.enterText(_keyed('blank-answer-'), 'capital');
      await tester.pumpAndSettle();
      expect(alt().enabled, isTrue);
      await tester.enterText(_keyed('blank-alternative-'), 'Capital');
      await tester.pumpAndSettle();
      expect(seen.last.answer, ['capital', 'Capital']);
      expect(find.text(_en.createTestValidationAnswerMissing), findsNothing);
    });
  });

  group('matching', () {
    test("two empty pairs to start; the web's checks", () {
      final q = DraftQuestion.create('matching-ordering');
      expect(q.left, hasLength(2));
      expect(q.right, hasLength(2));
      expect(
        questionProblems(q),
        containsAll([
          'titleText',
          'leftEmpty:1',
          'leftEmpty:2',
          'rightEmpty:1',
          'rightEmpty:2',
        ]),
      );
      // An image does not stand in for the text here.
      expect(
        questionProblems(q.copyWith(image: 'https://cdn.test/a.jpg')),
        contains('titleText'),
      );
      expect(
        questionProblems(q.copyWith(left: q.left.take(1).toList())),
        contains('pairs'),
      );
    });

    test('pairs are sent in order, left::right', () {
      final q = DraftQuestion.create('matching-ordering');
      final l = [for (final o in q.left) o.copyWith(text: 'L')];
      final r = [for (final o in q.right) o.copyWith(text: 'R')];
      final body = q.copyWith(text: 'Match', left: l, right: r).toBody();
      expect((body['matchingOptions']! as Map)['left'], [
        for (final o in l) {'id': o.id, 'text': 'L'},
      ]);
      expect(body['answer'], {
        'type': 'matchingOrdering',
        'value': [for (var i = 0; i < 2; i++) '${l[i].id}::${r[i].id}'],
      });
    });

    test('a draft with pairs survives being written and read', () {
      final q = DraftQuestion.create('matching-ordering').copyWith(text: 'M');
      expect(DraftQuestion.fromJson(q.toJson()).toJson(), q.toJson());
    });

    test('changing type keeps the text and resets the answer', () {
      final q = DraftQuestion.create('fill-in-the-blanks')
          .copyWith(text: 'T', answer: ['a', '']);
      final m = q.withSubType('matching-ordering');
      expect(m.text, 'T');
      expect(m.left, hasLength(2));
      expect(m.answer, isEmpty);
      final back = m.withSubType('fill-in-the-blanks');
      expect(back.left, isEmpty);
      expect(back.answer, ['', '']);
    });

    testWidgets('add and remove pairs, up to five', (tester) async {
      final seen = await _edit(
        tester,
        DraftQuestion.create('matching-ordering'),
      );
      expect(find.text(_en.createTestCardMatchingHint), findsOneWidget);
      final add = find.byKey(Key('pair-add-${seen.last.id}'));
      for (var i = 0; i < 3; i++) {
        await tester.tap(add);
        await tester.pumpAndSettle();
      }
      expect(seen.last.left, hasLength(5));
      expect(seen.last.right, hasLength(5));
      expect(find.text(_en.createTestCardMaxPairs(5)), findsOneWidget);

      await tester.tap(find.byKey(Key('pair-delete-${seen.last.id}-0')));
      await tester.pumpAndSettle();
      expect(seen.last.left, hasLength(4));

      await tester.enterText(_keyed('pair-left-').first, 'Dhaka');
      await tester.pumpAndSettle();
      await tester.enterText(_keyed('pair-right-').first, 'Bangladesh');
      await tester.pumpAndSettle();
      expect(seen.last.left.first.text, 'Dhaka');
      expect(seen.last.right.first.text, 'Bangladesh');
    });

    testWidgets('two pairs cannot be removed', (tester) async {
      final seen = await _edit(
        tester,
        DraftQuestion.create('matching-ordering'),
      );
      final remove = tester.widget<IconButton>(
        find.byKey(Key('pair-delete-${seen.last.id}-0')),
      );
      expect(remove.onPressed, isNull);
    });

    testWidgets('a 360 px phone stacks each pair', (tester) async {
      await _edit(
        tester,
        DraftQuestion.create('matching-ordering'),
        width: 360,
      );
      expect(tester.takeException(), isNull);
      final left = tester.getTopLeft(_keyed('pair-left-').first);
      final right = tester.getTopLeft(_keyed('pair-right-').first);
      expect(right.dy, greaterThan(left.dy));
    });
  });

  testWidgets('the type list offers blanks and matching', (tester) async {
    await _edit(tester, DraftQuestion.multipleChoice());
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text(_en.createTestTypesGradedFillInTheBlanks), findsWidgets);
    await tester.tap(find.text(_en.createTestTypesGradedMatchingOrdering).last);
    await tester.pumpAndSettle();
    expect(find.text(_en.createTestCardMatchingHint), findsOneWidget);
  });
}

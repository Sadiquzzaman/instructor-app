import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/files/file_picking.dart';
import 'package:instructor_app/core/files/local_file.dart';
import 'package:instructor_app/features/tests/data/test_draft.dart';
import 'package:instructor_app/features/tests/screens/question_editor.dart';
import 'package:instructor_app/features/shell/data/entitlements.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

class _Picking implements FilePicking {
  @override
  Future<LocalFile?> takePhoto() async => LocalFile.bytes('fig.jpg', [1, 2]);
  @override
  Future<List<LocalFile>> choosePhotos({int? limit}) async => [
    LocalFile.bytes('fig.jpg', [1, 2]),
  ];
  @override
  Future<List<LocalFile>> chooseFiles(List<String> extensions) async => [];
}

/// The editor alone, with the question kept in a test-local holder.
Future<List<DraftQuestion>> _edit(
  WidgetTester tester,
  DraftQuestion start, {
  bool images = false,
}) async {
  final seen = <DraftQuestion>[start];
  final api = FakeApi()
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
      (_) => ok({
        'id': 'f1',
        'name': 'fig.jpg',
        'mime': 'image/jpeg',
        'url': 'https://cdn.test/fig.jpg',
      }),
    );
  final container = await pumpInstructorApp(
    tester,
    api: api,
    session: testSession(),
    overrides: [
      filePickingProvider.overrideWithValue(_Picking()),
      entitlementsProvider.overrideWith(
        (ref) async => Entitlements(
          features: {'allow_question_images': images},
          limits: const {},
        ),
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

void main() {
  group('types, as the web builds them', () {
    test('choice types start with three options; true/false its three', () {
      expect(DraftQuestion.create('multiple-choice').options, hasLength(3));
      expect(DraftQuestion.create('true-false').options.map((o) => o.text), [
        'True',
        'False',
        'Not Given',
      ]);
    });

    test('choice to choice keeps options; to true/false they are fixed', () {
      final mr = DraftQuestion.create('multiple-response');
      final picked = mr.copyWith(answer: [mr.options[0].id, mr.options[1].id]);
      final mc = picked.withSubType('multiple-choice');
      expect(mc.options, mr.options);
      expect(mc.answer, [mr.options[0].id]);
      final tf = mc.withSubType('true-false');
      expect(tf.options.map((o) => o.text), trueFalseOptions);
      expect(tf.answer, isEmpty);
    });

    test('problems: 3 to 5 options, two right for multiple response', () {
      var q = DraftQuestion.create('multiple-response').copyWith(text: 'Q');
      q = q.copyWith(
        options: [for (final o in q.options) o.copyWith(text: 'x')],
      );
      expect(questionProblems(q.copyWith(answer: [q.options.first.id])), [
        'pickTwo',
      ]);
      expect(
        questionProblems(q.copyWith(options: q.options.take(2).toList())),
        contains('optionCount'),
      );
      final tf = DraftQuestion.create('true-false').copyWith(text: 'Q');
      expect(questionProblems(tf), ['pickOne']);
      expect(
        questionProblems(tf.copyWith(answer: [tf.options.first.id])),
        isEmpty,
      );
    });
  });

  testWidgets('true/false: the options are fixed; one is marked', (
    tester,
  ) async {
    final seen = await _edit(tester, DraftQuestion.create('true-false'));
    expect(find.text('Not Given'), findsOneWidget);
    expect(find.text(_en.createTestValidationFixedOptions), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is TextField && '${w.key}'.contains('option-text-'),
      ),
      findsNothing,
    );
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(seen.last.answer, [seen.last.options.first.id]);
  });

  testWidgets('add up to five options, keep at least three', (tester) async {
    final seen = await _edit(tester, DraftQuestion.create('multiple-choice'));
    final add = find.byKey(Key('option-add-${seen.last.id}'));
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(seen.last.options, hasLength(5));
    expect(tester.widget<TextButton>(add).onPressed, isNull);
    expect(find.text(_en.createTestCardMaxOptions(5)), findsOneWidget);
  });

  testWidgets('change the type to multiple response', (tester) async {
    final seen = await _edit(tester, DraftQuestion.create('multiple-choice'));
    await tester.tap(find.byKey(Key('question-type-${seen.last.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.createTestTypesGradedMultipleResponse).last);
    await tester.pumpAndSettle();
    expect(seen.last.subType, 'multiple-response');
  });

  testWidgets('a question image when the plan allows it', (tester) async {
    final seen = await _edit(
      tester,
      DraftQuestion.create('multiple-choice'),
      images: true,
    );
    await tester.tap(find.byKey(const Key('attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.appAttachChoosePhotos));
    await tester.pumpAndSettle();
    expect(seen.last.image, 'https://cdn.test/fig.jpg');
    expect(seen.last.toBody()['image'], 'https://cdn.test/fig.jpg');
  });

  testWidgets('no image without the plan feature', (tester) async {
    await _edit(tester, DraftQuestion.create('multiple-choice'));
    expect(find.byKey(const Key('attach')), findsNothing);
  });
}

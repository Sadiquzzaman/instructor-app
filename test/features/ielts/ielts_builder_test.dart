import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/ielts/data/builder.dart';
import 'package:instructor_app/features/ielts/data/recording.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';
import 'ielts_overview_test.dart' show ieltsMember;

final _en = AppLocalizationsEn();

Map<String, Object?> _test({
  String status = 'DRAFT',
  bool canEdit = true,
  String passage = '<p>Bees live in hives.</p>',
}) => {
  'id': 't1',
  'title': 'Reading set 1',
  'purpose': 'PRACTICE',
  'test_type': 'ACADEMIC',
  'status': status,
  'modules': ['READING'],
  'durations': {'READING': 1200},
  'can_edit': canEdit,
  'needs_review': false,
  'parts': [
    {
      'id': 'p1',
      'module': 'READING',
      'part_no': 1,
      'title': 'Bees',
      'content': passage,
      'audio_file_id': null,
      'image_file_id': null,
      'groups': [
        {
          'id': 'g1',
          'type': 'TFNG',
          'instruction': 'Do the statements agree?',
          'word_limit': null,
          'shared': null,
          'image_file_id': null,
          'number_from': 1,
          'number_to': 2,
          'questions': [
            {
              'id': 'q1',
              'prompt': 'Bees live in hives.',
              'options': null,
              'answer': {
                'keys': ['TRUE'],
              },
              'number_from': 1,
              'number_to': 1,
            },
            {
              'id': 'q2',
              'prompt': 'Bees are fish.',
              'options': null,
              'answer': {
                'keys': ['FALSE'],
              },
              'number_from': 2,
              'number_to': 2,
            },
          ],
        },
      ],
    },
  ],
};

FakeApi _api({Map<String, Object?>? test, FakeHandler? publish}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on(
    'GET /me/entitlements',
    (_) => ok({
      'features': {'ielts': true},
    }),
  )
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on('GET /ielts/tests/t1', (_) => ok(test ?? _test()))
  ..on('GET /ielts/tests', (_) => ok(<Object>[]))
  ..on('PUT /ielts/tests/t1/parts/p1', (_) => ok(_test()))
  ..on('POST /ielts/tests/t1/parts/p1/groups', (_) => ok(_test()))
  ..on('PUT /ielts/tests/t1/groups/g1', (_) => ok(_test()))
  ..on('PATCH /ielts/tests/t1', (_) => ok(_test()))
  ..on(
    'POST /ielts/tests/t1/publish',
    publish ??
        (_) => apiError(
          422,
          code: 'IELTS_TEST_INCOMPLETE',
          details: {
            'problems': [
              {'module': 'READING', 'part_no': 1, 'problem': 'NO_QUESTIONS'},
              {
                'module': 'LISTENING',
                'part_no': null,
                'problem': 'NOT_40',
                'count': 12,
              },
            ],
          },
        ),
  );

class _FakePlayer implements RecordingPlayer {
  final played = <Uri>[];

  @override
  Future<void> play(Uri uri) async => played.add(uri);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

Future<void> _open(
  WidgetTester tester,
  FakeApi api, {
  String? lang,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: ieltsMember('TEACHER'),
    prefs: {'language': ?lang},
    overrides: overrides,
  );
  app.read(routerProvider).go('/ielts/tests/t1');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('group bodies, as the web sends them', () {
    test('multiple choice: own options, one key', () {
      final b = groupBody(
        type: 'MCQ_SINGLE',
        instruction: ' Choose ',
        questions: [
          QuestionDraft(prompt: 'Why?', keys: ['B']),
        ],
      );
      expect(b['instruction'], 'Choose');
      expect(b['word_limit'], isNull);
      expect(b['shared'], isNull);
      final q = (b['questions']! as List).single as Map;
      expect(q['options'], hasLength(4));
      expect(q['answer'], {
        'keys': ['B'],
      });
    });

    test('completion: accepted spellings, word limit, text with gaps', () {
      final b = groupBody(
        type: 'SUMMARY_COMPLETION',
        instruction: 'Complete',
        wordLimit: 2,
        sharedText: 'Bees make [[1]].',
        questions: [
          QuestionDraft(accepted: [' honey ', 'Honey', ' ']),
        ],
      );
      expect(b['word_limit'], 2);
      expect(b['shared'], {'text': 'Bees make [[1]].'});
      final q = (b['questions']! as List).single as Map;
      expect(q['options'], isNull);
      expect(q['prompt'], isNull);
      expect(q['answer'], {
        'accepted': ['honey', 'Honey'],
      });
    });

    test('a word box sends keys and no word limit', () {
      final b = groupBody(
        type: 'NOTE_COMPLETION',
        instruction: 'Choose from the box',
        wordLimit: 3,
        wordBox: true,
        sharedOptions: [(key: 'A', text: 'honey'), (key: 'B', text: 'wax')],
        questions: [
          QuestionDraft(id: 'q9', keys: ['A']),
        ],
      );
      expect(b['word_limit'], isNull);
      expect((b['shared']! as Map)['options'], [
        {'key': 'A', 'text': 'honey'},
        {'key': 'B', 'text': 'wax'},
      ]);
      expect(((b['questions']! as List).single as Map)['id'], 'q9');
    });

    test('types per module and letters', () {
      expect(groupTypesFor('READING'), contains('TFNG'));
      expect(groupTypesFor('LISTENING'), isNot(contains('TFNG')));
      expect(groupTypesFor('LISTENING'), contains('FORM_COMPLETION'));
      expect(groupTypesFor('READING'), isNot(contains('FORM_COMPLETION')));
      expect(groupTypesFor('READING'), hasLength(15));
      expect(nextKey(['A', 'B', 'D']), 'C');
      expect(isCompletion('SHORT_ANSWER'), isFalse);
      expect(isCompletion('TABLE_COMPLETION'), isTrue);
    });
  });

  testWidgets('a draft: save a part as simple HTML', (tester) async {
    final api = _api();
    await _open(tester, api);
    expect(find.text('Reading set 1'), findsOneWidget);
    expect(find.text(_en.ieltsBuilderQuestionRange(1, 2)), findsOneWidget);
    expect(find.textContaining('Bees are fish. → FALSE'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('part-content-p1')),
      'Bees live in hives.\n\nThey make honey.',
    );
    await _tap(tester, find.byKey(const Key('part-save-p1')));
    expect(api.to('PUT /ielts/tests/t1/parts/p1').single.body, {
      'title': 'Bees',
      'content': '<p>Bees live in hives.</p><p>They make honey.</p>',
    });
  });

  testWidgets('publish lists what is missing', (tester) async {
    await _open(tester, _api());
    await _tap(tester, find.byKey(const Key('builder-publish')));
    expect(find.byKey(const Key('builder-problems')), findsOneWidget);
    expect(
      find.textContaining(
        _en.ieltsBuilderProblemsNOQUESTIONS('Passage 1', 'Reading'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(_en.ieltsBuilderProblemsNOT40('Listening', 12)),
      findsOneWidget,
    );
  });

  testWidgets('add a question group: True / False / Not Given', (tester) async {
    final api = _api();
    await _open(tester, api);
    await _tap(tester, find.byKey(const Key('group-add-p1')));
    await tester.tap(find.byKey(const Key('group-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.ieltsBuilderGroupTypesTFNG).last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('group-instruction')),
      'Agree or not?',
    );
    await tester.enterText(
      find.byKey(const Key('question-prompt-0')),
      'Bees sleep.',
    );
    await _tap(tester, find.byKey(const Key('question-answer-0')));
    await tester.tap(find.text('NOT GIVEN').last);
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('group-save')));
    final body =
        api.to('POST /ielts/tests/t1/parts/p1/groups').single.body! as Map;
    expect(body['type'], 'TFNG');
    expect(body['instruction'], 'Agree or not?');
    final q = (body['questions'] as List).single as Map;
    expect(q['prompt'], 'Bees sleep.');
    expect(q['options'], isNull);
    expect(q['answer'], {
      'keys': ['NOT GIVEN'],
    });
  });

  testWidgets('editing a group keeps its questions and their ids', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    await _tap(tester, find.byKey(const Key('group-edit-g1')));
    await _tap(tester, find.byKey(const Key('group-save')));
    final body = api.to('PUT /ielts/tests/t1/groups/g1').single.body! as Map;
    expect(
      [for (final q in body['questions'] as List) (q as Map)['id']],
      ['q1', 'q2'],
    );
    expect(((body['questions'] as List).last as Map)['answer'], {
      'keys': ['FALSE'],
    });
  });

  testWidgets('a passage with formatting is shown, not edited', (tester) async {
    final api = _api(test: _test(passage: '<p><strong>Bees</strong></p>'));
    await _open(tester, api);
    expect(find.byKey(const Key('part-content-p1')), findsNothing);
    expect(find.text(_en.appIeltsPartFormatted), findsOneWidget);
    await _tap(tester, find.byKey(const Key('part-save-p1')));
    // Only the title goes; the web's text is left as it is.
    expect(api.to('PUT /ielts/tests/t1/parts/p1').single.body, {
      'title': 'Bees',
    });
  });

  testWidgets('the recording of a part plays in the app', (tester) async {
    final t = _test(status: 'PUBLISHED');
    final part = (t['parts']! as List).first as Map;
    part['audio_file_id'] = 'au1';
    part['module'] = 'LISTENING';
    t['modules'] = ['LISTENING'];
    t['durations'] = {'LISTENING': 1800};
    final player = _FakePlayer();
    await _open(
      tester,
      _api(test: t),
      overrides: [recordingPlayerProvider.overrideWithValue(() => player)],
    );
    await _tap(tester, find.byKey(const Key('recording-au1')));
    expect(player.played.single.path, endsWith('/files/au1/content'));
  });

  testWidgets('published, or someone else\'s: read-only', (tester) async {
    await _open(tester, _api(test: _test(status: 'PUBLISHED')));
    expect(find.text(_en.ieltsBuilderLockedPublished), findsOneWidget);
    expect(find.byKey(const Key('part-save-p1')), findsNothing);
    expect(find.byKey(const Key('builder-unpublish')), findsOneWidget);
    expect(find.byKey(const Key('builder-openings')), findsOneWidget);

    await _open(tester, _api(test: _test(canEdit: false)));
    expect(find.text(_en.ieltsBuilderLockedNotYours), findsOneWidget);
    expect(find.byKey(const Key('builder-details')), findsNothing);
  });

  testWidgets('details: title, type and minutes while a draft', (tester) async {
    final api = _api();
    await _open(tester, api);
    await _tap(tester, find.byKey(const Key('builder-details')));
    await tester.enterText(
      find.byKey(const Key('details-minutes-READING')),
      '25',
    );
    await _tap(tester, find.byKey(const Key('details-save')));
    expect(api.to('PATCH /ielts/tests/t1').single.body, {
      'title': 'Reading set 1',
      'test_type': 'ACADEMIC',
      'durations': {'READING': 1500},
    });
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    final bn = AppLocalizationsBn();
    final app = await pumpInstructorApp(
      tester,
      api: _api(),
      session: ieltsMember('TEACHER'),
      prefs: {'language': 'bn'},
    );
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    app.read(routerProvider).go('/ielts/tests/t1');
    await tester.pumpAndSettle();
    expect(find.text(bn.ieltsBuilderPublish), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('group-add-p1')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

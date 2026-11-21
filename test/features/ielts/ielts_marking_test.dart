import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';
import 'ielts_overview_test.dart' show ieltsMember;

final _en = AppLocalizationsEn();

Map<String, Object?> _view({List<Object> marks = const []}) => {
  'attempt_id': 'w9',
  'module': 'WRITING',
  'status': 'SUBMITTED',
  'student': {'id': 's1', 'full_name': 'Tania Akter'},
  'test': {'id': 't1', 'title': 'Writing practice'},
  'batch': 'Evening A',
  'submitted_at': '2026-11-25T05:00:00.000Z',
  'band': null,
  'test_type': 'ACADEMIC',
  'tasks': [
    {
      'part_id': 'k1',
      'part_no': 1,
      'title': null,
      'content': '<p>Describe the chart.</p>',
      'image_file_id': null,
      'script': 'The chart shows sales.',
      'words': 4,
      'min_words': 150,
    },
    {
      'part_id': 'k2',
      'part_no': 2,
      'title': null,
      'content': '<p>Discuss both views.</p>',
      'image_file_id': null,
      'script': 'Some people think…',
      'words': 3,
      'min_words': 250,
    },
  ],
  'marks': marks,
  'speaking': null,
  'feedback': null,
  'marked_by': null,
  'marked_at': null,
};

FakeApi _api() => FakeApi()
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
  ..on(
    'GET /ielts/marking',
    (r) => ok([
      {
        'attempt_id': r.query['module'] == 'SPEAKING' ? 'x7' : 'w9',
        'module': r.query['module'],
        'status': r.query['state'] == 'MARKED' ? 'MARKED' : 'SUBMITTED',
        'student': {'id': 's1', 'full_name': 'Tania Akter'},
        'test': {'id': 't1', 'title': 'Writing practice'},
        'batch': 'Evening A',
        'submitted_at': '2026-11-25T05:00:00.000Z',
        'band': r.query['state'] == 'MARKED' ? 6.5 : null,
      },
    ]),
  )
  ..on('GET /ielts/marking/w9', (_) => ok(_view()))
  ..on('PUT /ielts/marking/w9/writing', (_) => ok(_view()));

Future<FakeApi> _open(WidgetTester tester, String route, {String? lang}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = _api();
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: ieltsMember('TEACHER'),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go(route);
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
  return api;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _band(WidgetTester tester, String key, String band) async {
  await _tap(tester, find.byKey(Key(key)));
  await tester.tap(find.text(band).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the list: Writing or Speaking, waiting or marked', (
    tester,
  ) async {
    final api = await _open(tester, '/ielts/marking');
    expect(find.text('Tania Akter'), findsOneWidget);
    expect(find.text(_en.ieltsMarkingMark), findsOneWidget);
    expect(api.to('GET /ielts/marking').last.query, {
      'state': 'WAITING',
      'module': 'WRITING',
    });
    await _tap(tester, find.byKey(const Key('marking-state-MARKED')));
    expect(find.text(_en.ieltsMarkingChange), findsOneWidget);
    await _tap(tester, find.text(_en.ieltsMarkingModulesSPEAKING));
    expect(api.to('GET /ielts/marking').last.query['module'], 'SPEAKING');
  });

  testWidgets('mark Writing: criteria per task, the bands, comments', (
    tester,
  ) async {
    final api = await _open(tester, '/ielts/marking/w9');
    expect(find.text(_en.ieltsMarkingMarkTitle('Tania Akter')), findsOneWidget);
    expect(find.text('The chart shows sales.'), findsOneWidget);
    expect(
      find.text(
        '${_en.ieltsTakeWordCount(4)} · ${_en.ieltsTakeUnderMinimum(150)}',
      ),
      findsOneWidget,
    );
    final save = find.byKey(const Key('writing-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    // Task 1: TA, CC, LR, GRA; Task 2: TR, CC, LR, GRA.
    for (final k in ['TA', 'CC', 'LR', 'GRA']) {
      await _band(tester, 'criterion-k1-$k', '6.0');
    }
    expect(find.text(_en.ieltsTakeTaskBand('6.0')), findsOneWidget);
    for (final (k, b) in [
      ('TR', '7.0'),
      ('CC', '6.5'),
      ('LR', '6.5'),
      ('GRA', '6.0'),
    ]) {
      await _band(tester, 'criterion-k2-$k', b);
    }
    // (7 + 6.5 + 6.5 + 6) / 4 = 6.5.
    expect(find.text(_en.ieltsTakeTaskBand('6.5')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('comment-k1')), 'Too short.');
    await tester.enterText(
      find.byKey(const Key('writing-feedback')),
      'Write more.',
    );
    await _tap(tester, save);
    expect(api.to('PUT /ielts/marking/w9/writing').single.body, {
      'tasks': [
        {
          'part_id': 'k1',
          'criteria': {'TA': 6, 'CC': 6, 'LR': 6, 'GRA': 6},
          'comment': 'Too short.',
        },
        {
          'part_id': 'k2',
          'criteria': {'TR': 7, 'CC': 6.5, 'LR': 6.5, 'GRA': 6},
        },
      ],
      'feedback': 'Write more.',
    });
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    final bn = AppLocalizationsBn();
    await _open(tester, '/ielts/marking', lang: 'bn');
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    await tester.pumpAndSettle();
    expect(find.text(bn.ieltsMarkingTitle), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/ielts/data/ielts_tests.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';
import 'ielts_overview_test.dart' show ieltsMember;

final _en = AppLocalizationsEn();

Map<String, Object?> _test({
  String id = 't1',
  String purpose = 'MOCK',
  String status = 'DRAFT',
}) => {
  'id': id,
  'title': 'Full mock $id',
  'purpose': purpose,
  'test_type': 'ACADEMIC',
  'modules': ['LISTENING', 'READING', 'WRITING', 'SPEAKING'],
  'question_counts': {'LISTENING': 40, 'READING': 12},
  'status': status,
  'updated_at': '2026-11-20T04:00:00.000Z',
  'needs_review': false,
};

List<Map<String, Object?>> _tables() => [
  {
    'module': 'LISTENING',
    'test_type': null,
    'customised': true,
    'rows': [
      {'min_raw': 39, 'band': 9},
      {'min_raw': 30, 'band': 7},
      {'min_raw': 0, 'band': 0},
    ],
  },
  {
    'module': 'READING',
    'test_type': 'ACADEMIC',
    'customised': false,
    'rows': [
      {'min_raw': 30, 'band': 7},
      {'min_raw': 0, 'band': 0},
    ],
  },
];

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
    'GET /ielts/tests',
    (_) =>
        ok([_test(), _test(id: 't2', purpose: 'PRACTICE', status: 'ARCHIVED')]),
  )
  ..on(
    'GET /ielts/old-exams',
    (_) => ok([
      {
        'id': 'x1',
        'title': 'Old reading exam',
        'created_at': '2026-10-01T04:00:00.000Z',
        'converted_test_id': null,
      },
    ]),
  )
  ..on(
    'POST /ielts/old-exams/x1/convert',
    (_) => ok({
      'test_id': 't9',
      'converted': 10,
      'skipped': [
        {'question_id': 'q4', 'reason': 'An essay question'},
      ],
    }),
  )
  ..on('POST /ielts/tests', (_) => ok({'id': 't5'}))
  ..on('POST /ielts/tests/t1/duplicate', (_) => ok({'id': 't6'}))
  ..on('POST /ielts/tests/t1/archive', (_) => ok(null))
  ..on('DELETE /ielts/tests/t1', (_) => ok(null))
  ..on('GET /ielts/band-tables', (_) => ok(_tables()))
  ..on('PUT /ielts/band-tables', (r) => ok(r.body))
  ..on('POST /ielts/band-tables/reset', (_) => ok(null));

Future<void> _open(
  WidgetTester tester,
  FakeApi api,
  String role,
  String route, {
  String? lang,
}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: ieltsMember(role),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go(route);
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      f,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('bodies and rules', () {
    test('a mock takes its modules; a practice set its parts', () {
      expect(
        newTestBody(
          title: ' Mock 1 ',
          testType: 'ACADEMIC',
          purpose: 'MOCK',
          modules: ['READING', 'LISTENING'],
        ),
        {
          'title': 'Mock 1',
          'test_type': 'ACADEMIC',
          'purpose': 'MOCK',
          'modules': ['LISTENING', 'READING'],
        },
      );
      expect(
        newTestBody(
          title: 'P',
          testType: 'GENERAL',
          purpose: 'PRACTICE',
          module: 'READING',
          parts: [3, 1],
        ),
        {
          'title': 'P',
          'test_type': 'GENERAL',
          'purpose': 'PRACTICE',
          'module': 'READING',
          'part_nos': [1, 3],
        },
      );
    });

    test('a band table runs from 40 down to 0, bands never going up', () {
      expect(
        bandRowsValid([(minRaw: 30, band: 7), (minRaw: 0, band: 0)]),
        isTrue,
      );
      expect(
        bandRowsValid([(minRaw: 30, band: 7), (minRaw: 5, band: 2)]),
        isFalse,
      );
      expect(
        bandRowsValid([(minRaw: 10, band: 5), (minRaw: 20, band: 6)]),
        isFalse,
      );
      expect(
        bandRowsValid([(minRaw: 30, band: 6), (minRaw: 0, band: 7)]),
        isFalse,
      );
      expect(
        bandRowsValid([(minRaw: 41, band: 9), (minRaw: 0, band: 0)]),
        isFalse,
      );
      expect(bandRowsValid([]), isFalse);
    });
  });

  testWidgets('tests: questions per module, filter, copy, archive, delete', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, 'TEACHER', '/ielts/tests');
    expect(find.text('Full mock t1'), findsOneWidget);
    expect(
      find.textContaining('Listening 40/40 · Reading 12/40'),
      findsOneWidget,
    );
    // Archived: nothing to archive.
    expect(find.byKey(const Key('ielts-test-archive-t2')), findsNothing);

    await _tap(tester, find.byKey(const Key('ielts-test-purpose')));
    await tester.tap(find.text(_en.ieltsTestsPurposesMOCK).last);
    await tester.pumpAndSettle();
    expect(api.to('GET /ielts/tests').last.query['purpose'], 'MOCK');

    await _tap(tester, find.byKey(const Key('ielts-test-archive-t1')));
    expect(api.to('POST /ielts/tests/t1/archive'), hasLength(1));

    await _tap(tester, find.byKey(const Key('ielts-test-delete-t1')));
    expect(
      find.text(_en.ieltsTestsDeleteDescription('Full mock t1')),
      findsOneWidget,
    );
    await _tap(tester, find.byKey(const Key('ielts-test-delete-confirm')));
    expect(api.to('DELETE /ielts/tests/t1'), hasLength(1));

    await _tap(tester, find.byKey(const Key('ielts-test-copy-t1')));
    expect(api.to('POST /ielts/tests/t1/duplicate'), hasLength(1));
  });

  testWidgets('a new practice set: one module, its parts', (tester) async {
    final api = _api();
    await _open(tester, api, 'OWNER', '/ielts/tests');
    await _tap(tester, find.byKey(const Key('ielts-test-new')));
    final create = find.byKey(const Key('ielts-new-create'));
    expect(tester.widget<FilledButton>(create).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('ielts-new-title')), 'Set 1');
    await tester.pump();
    await _tap(tester, find.byKey(const Key('ielts-new-purpose-PRACTICE')));
    // Reading has three passages.
    expect(find.byKey(const Key('ielts-new-part-3')), findsOneWidget);
    expect(find.byKey(const Key('ielts-new-part-4')), findsNothing);
    await _tap(tester, find.byKey(const Key('ielts-new-part-2')));
    await _tap(tester, create);
    expect(api.to('POST /ielts/tests').single.body, {
      'title': 'Set 1',
      'test_type': 'ACADEMIC',
      'purpose': 'PRACTICE',
      'module': 'READING',
      'part_nos': [1, 2],
    });
  });

  testWidgets('an old exam is copied into the new format', (tester) async {
    final api = _api();
    await _open(tester, api, 'OWNER', '/ielts/tests');
    await _tap(tester, find.byKey(const Key('ielts-convert-x1')));
    expect(api.to('POST /ielts/old-exams/x1/convert'), hasLength(1));
    expect(find.text(_en.ieltsConvertDoneDescription(10)), findsOneWidget);
    expect(find.textContaining('An essay question'), findsOneWidget);
  });

  testWidgets('band tables: owners change and reset; others read', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, 'OWNER', '/ielts/band-tables');
    expect(find.text(_en.ieltsBandsCustomised), findsOneWidget);
    // A row that breaks the rule turns the rule red and stops saving.
    await tester.enterText(
      find.byKey(const Key('band-raw-READING-ACADEMIC-1')),
      '40',
    );
    await tester.pump();
    final save = find.byKey(const Key('band-save-READING-ACADEMIC'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('band-raw-READING-ACADEMIC-1')),
      '0',
    );
    await tester.pump();
    await _tap(tester, save);
    expect(api.to('PUT /ielts/band-tables').single.body, {
      'module': 'READING',
      'test_type': 'ACADEMIC',
      'rows': [
        {'min_raw': 30, 'band': 7},
        {'min_raw': 0, 'band': 0},
      ],
    });
    await _tap(tester, find.byKey(const Key('band-reset-LISTENING-')));
    expect(api.to('POST /ielts/band-tables/reset').single.body, {
      'module': 'LISTENING',
    });
  });

  testWidgets('a teacher reads the band tables', (tester) async {
    await _open(tester, _api(), 'TEACHER', '/ielts/band-tables');
    expect(find.text(_en.ieltsBandsReadOnly), findsOneWidget);
    expect(find.byKey(const Key('band-save-LISTENING-')), findsNothing);
    expect(find.text('9.0'), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), 'OWNER', '/ielts/tests', lang: 'bn');
    expect(find.text(bn.ieltsTestsPageTitle), findsWidgets);
    expect(tester.takeException(), isNull);
    await _open(tester, _api(), 'OWNER', '/ielts/band-tables', lang: 'bn');
    expect(tester.takeException(), isNull);
  });
}

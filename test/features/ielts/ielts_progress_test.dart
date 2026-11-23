import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';
import 'ielts_overview_test.dart' show ieltsMember;

final _en = AppLocalizationsEn();

Map<String, Object?> _progress() => {
  'profile': {
    'student': {'id': 's1', 'full_name': 'Tania Akter'},
    'target_overall': 7,
    'target_bands': {'WRITING': 6.5},
  },
  'modules': {
    'LISTENING': [
      {
        'attempt_id': 'a',
        'test_title': 'Mock 1',
        'band': 6,
        'at': '2026-10-01T04:00:00.000Z',
      },
      {
        'attempt_id': 'b',
        'test_title': 'Mock 2',
        'band': 7.5,
        'at': '2026-11-01T04:00:00.000Z',
      },
    ],
    'READING': <Object>[],
    'WRITING': <Object>[],
    'SPEAKING': <Object>[],
  },
  'mocks': [
    {
      'assignment_id': 'o1',
      'test_title': 'Mock 2',
      'bands': {'LISTENING': 7.5, 'READING': 7, 'WRITING': 6, 'SPEAKING': 6.5},
      'overall': 7,
      'at': '2026-11-01T04:00:00.000Z',
    },
  ],
  'question_types': [
    {'type': 'TFNG', 'right': 3, 'total': 8, 'percent': 38},
  ],
};

Map<String, Object?> _report() => {
  'student': {'id': 's1', 'full_name': 'Tania Akter', 'batch': 'Evening A'},
  'test': {'id': 't1', 'title': 'Mock 2', 'test_type': 'ACADEMIC'},
  'window': {'opens_at': '2026-11-01T03:00:00.000Z'},
  'modules': {
    'LISTENING': {'band': 7.5, 'raw_score': 32, 'raw_total': 40},
    'WRITING': {
      'band': 6,
      'criteria': {
        'tasks': [
          {
            'part_no': 1,
            'band': 6,
            'criteria': {'TA': 6, 'CC': 6, 'LR': 6, 'GRA': 6},
            'comment': 'Describe the trends.',
          },
        ],
      },
      'feedback': 'Plan first.',
    },
  },
  'overall': 7,
  'targets': {
    'overall': 7,
    'bands': {'WRITING': 6.5},
  },
  'test_date': '2026-12-20',
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
  ..on('GET /ielts/progress/me', (_) => ok(_progress()))
  ..on('GET /ielts/progress/s1', (_) => ok(_progress()))
  ..on('GET /ielts/report/o1/s1', (_) => ok(_report()))
  ..on(
    'GET /integrity/checks/latest',
    (_) => ok({'check': null, 'students': <Object>[], 'pairs': <Object>[]}),
  );

Future<FakeApi> _open(
  WidgetTester tester,
  String role,
  String route, {
  String? lang,
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = _api();
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
  return api;
}

void main() {
  testWidgets('my progress: bands per module, mocks, weakest types', (
    tester,
  ) async {
    await _open(tester, 'STUDENT', '/ielts/progress');
    expect(find.text(_en.ieltsProgressTitle), findsWidgets);
    expect(find.text(_en.ieltsProgressTarget('7.0')), findsOneWidget);
    // Listening: two bands against the 7.0 target.
    expect(find.text('6.0'), findsOneWidget);
    expect(find.text('7.5'), findsOneWidget);
    // Writing has its own target but no bands yet.
    expect(find.text(_en.ieltsProgressNoBands), findsNWidgets(3));
    expect(
      find.textContaining('Mock 2 · ${_en.ieltsProgressOverall} 7.0'),
      findsOneWidget,
    );
    expect(find.text(_en.ieltsBuilderGroupTypesTFNG), findsOneWidget);
    expect(find.textContaining(_en.ieltsProgressRightOf(3, 8)), findsOneWidget);
  });

  testWidgets('staff open a student progress', (tester) async {
    await _open(tester, 'TEACHER', '/ielts/progress/s1');
    expect(find.text(_en.ieltsProgressTitleFor('Tania Akter')), findsOneWidget);
  });

  testWidgets('the band report: bands, targets, Writing marks', (tester) async {
    await _open(tester, 'TEACHER', '/ielts/report/o1/s1');
    expect(find.text(_en.ieltsReportTitle), findsOneWidget);
    expect(find.textContaining('Tania Akter · Evening A'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('report-band-LISTENING'))).data,
      '7.5',
    );
    expect(
      find.textContaining(_en.ieltsTakeScoreOutOf(32, 40)),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('report-overall'))).data,
      '7.0',
    );
    expect(find.text('Describe the trends.'), findsOneWidget);
    expect(find.text('Plan first.'), findsOneWidget);
  });

  testWidgets('Writing plagiarism uses the IELTS scope', (tester) async {
    final api = await _open(
      tester,
      'TEACHER',
      '/ielts/assignments/o1/similarity',
    );
    expect(api.to('GET /integrity/checks/latest').single.query, {
      'scope_type': 'IELTS_WRITING',
      'scope_id': 'o1',
    });
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    final bn = AppLocalizationsBn();
    await _open(tester, 'STUDENT', '/ielts/progress', lang: 'bn');
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    await tester.pumpAndSettle();
    expect(find.text(bn.ieltsProgressTitle), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/results/screens/results_screens.dart';
import 'package:instructor_app/features/results/screens/section_performance_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Session _teacher() =>
    Session.fromPayload({...sessionPayload(), 'role': 'TEACHER'});

Map<String, Object?> _line(num? score, {String? grade, num? att}) => {
  'exams_pct': score,
  'homework_pct': 80,
  'attendance_pct': att,
  'behaviour_pct': 70,
  'score_pct': score,
  'grade': grade == null ? null : {'grade': grade, 'gpa': 4},
  'counts': {'exams': 1, 'homework': 1, 'ratings': 1},
};

Map<String, Object?> _student(
  String id,
  String name,
  num? score, {
  String? grade,
  int? position,
  List<String> risk = const [],
  Map<String, Object?>? maths,
}) => {
  'student': {'id': id, 'full_name': name, 'roll_no': null},
  'overall': _line(score, grade: grade, att: 90),
  'subjects': [
    {
      ...maths ?? _line(score, grade: grade),
      'subject': {'id': 'm', 'name': 'Mathematics'},
    },
  ],
  'homework': {'set': 4, 'missing': 1, 'late': 0},
  'missing_homework': 1,
  'at_risk': risk,
  'position': position,
};

Map<String, Object?> _section() => {
  'section': {
    'id': 'sa',
    'name': 'A',
    'class_id': 'c6',
    'class_name': 'Class 6',
    'session_id': 'se1',
  },
  'period': {'from': '2026-01-01', 'to': '2026-12-31', 'term': null},
  'weights': {
    'exams_pct': 60,
    'homework_pct': 20,
    'attendance_pct': 10,
    'behaviour_pct': 10,
    'is_default': true,
  },
  'thresholds': {'score_pct': 40, 'attendance_pct': 75, 'missing_homework': 3},
  'subjects': [
    {'id': 'm', 'name': 'Mathematics'},
  ],
  'exams': <Object>[],
  'students': [
    _student('s2', 'Nadia Islam', 35, grade: 'F', position: 2, risk: ['SCORE']),
    _student('s1', 'Karim Hasan', 85, grade: 'A+', position: 1),
  ],
};

FakeApi _api() => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /scores/sections',
    (_) => ok({
      'session': {'id': 'se1', 'name': '2026', 'closed': false},
      'terms': [
        {'id': 't1', 'name': 'Term 1'},
      ],
      'sections': [
        {'id': 'sa', 'name': 'A', 'class_name': 'Class 6'},
      ],
    }),
  )
  ..on('GET /scores/sections/sa', (_) => ok(_section()))
  ..on(
    'GET /scores/students/s1',
    (_) => ok({
      'student': {'id': 's1', 'full_name': 'Karim Hasan', 'roll_no': null},
      'overall': _line(85, grade: 'A+', att: 90),
      'subjects': <Object>[],
      'exams': <Object>[],
      'position': 1,
      'class_size': 2,
    }),
  );

Future<void> _open(
  WidgetTester tester,
  FakeApi api,
  String route, {
  String? lang,
}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _teacher(),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go(route);
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

Finder _scrollable() => find.byType(Scrollable).first;

void main() {
  testWidgets('a section: summary, at risk, students by position', (
    tester,
  ) async {
    await _open(tester, _api(), '/performance');
    expect(find.byType(SectionPerformanceScreen), findsOneWidget);
    // Average of 85 and 35; highest; lowest.
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('85%'), findsWidgets);
    expect(find.text('35%'), findsWidgets);
    await tester.scrollUntilVisible(
      find.byKey(const Key('perf-at-risk')),
      200,
      scrollable: _scrollable(),
    );
    expect(find.text(_en.performanceRiskSCORE('35%')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('perf-student-s2')),
      200,
      scrollable: _scrollable(),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('perf-student-s1'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('perf-student-s2'))).dy),
    );
  });

  testWidgets('a term asks for that term', (tester) async {
    final api = _api();
    await _open(tester, api, '/performance');
    await tester.tap(find.byKey(const Key('perf-term')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Term 1').last);
    await tester.pumpAndSettle();
    expect(api.to('GET /scores/sections/sa').last.query['term_id'], 't1');
  });

  testWidgets('a student opens their page', (tester) async {
    await _open(tester, _api(), '/performance');
    await tester.scrollUntilVisible(
      find.byKey(const Key('perf-student-s1')),
      200,
      scrollable: _scrollable(),
    );
    await tester.ensureVisible(find.byKey(const Key('perf-student-s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('perf-student-s1')));
    await tester.pumpAndSettle();
    // The student's page replaced the section's.
    expect(find.byType(SectionPerformanceScreen), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is PerformanceScreen && w.studentId == 's1',
      ),
      findsOneWidget,
    );
    expect(find.text('Karim Hasan'), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), '/performance', lang: 'bn');
    expect(find.text(bn.performanceTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

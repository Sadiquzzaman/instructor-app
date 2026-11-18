import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/results/screens/results_screens.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import 'package:instructor_app/features/results/screens/section_performance_screen.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Map<String, Object?> _line(String? subject, num score, String grade) => {
  'exams_pct': 70,
  'homework_pct': 90,
  'attendance_pct': 95,
  'behaviour_pct': 80,
  'score_pct': score,
  'grade': {'grade': grade, 'gpa': 4},
  'counts': {'exams': 2, 'homework': 3, 'ratings': 1},
  if (subject != null) 'subject': {'id': subject, 'name': subject},
};

FakeApi _api({bool empty = false}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /calendar/me', (_) => ok({'items': <Object>[]}))
  ..on(
    'GET /offline-exams/mine',
    (_) => ok(
      empty
          ? <Object>[]
          : [
              {
                'exam': {
                  'id': 'o1',
                  'name': 'Half-yearly',
                  'exam_date': '2026-10-01',
                  'total_marks': 100,
                  'term': {'id': 't', 'name': 'Term 1'},
                  'subject': {'id': 's', 'name': 'Mathematics'},
                },
                'marks': 82,
                'is_absent': false,
                'percent': 82,
                'grade': {'grade': 'A', 'gpa': 4},
              },
              {
                'exam': {
                  'id': 'o2',
                  'name': 'Spelling',
                  'exam_date': '2026-10-02',
                  'total_marks': 20,
                  'term': null,
                  'subject': {'id': 'e', 'name': 'English'},
                },
                'marks': null,
                'is_absent': true,
                'percent': null,
                'grade': null,
              },
            ],
    ),
  )
  ..on(
    'GET /scores/students/user-1',
    (_) => ok({
      'overall': _line(null, 84.25, 'A'),
      'subjects': [_line('Mathematics', 90, 'A+'), _line('English', 70, 'B')],
      'position': 3,
      'class_size': 30,
      'homework': {'set': 3, 'missing': 0, 'late': 1, 'on_time_pct': 66.7},
      'exams': [
        {
          'id': 'x',
          'kind': 'PAPER',
          'name': 'Half-yearly',
          'date': '2026-10-01',
          'subject': {'id': 's', 'name': 'Mathematics'},
          'marks': 82,
          'total': 100,
          'percent': 82,
          'is_absent': false,
        },
      ],
      'published_only': true,
    }),
  )
  ..on(
    'GET /report-cards/mine',
    (_) => ok([
      {
        'id': 'rc1',
        'version': 1,
        'locale': 'en',
        'term': {'id': 't', 'name': 'Term 1'},
        'generated_at': '2026-11-01T06:00:00Z',
      },
    ]),
  )
  ..on(
    'GET /report-cards/rc1',
    (_) => ok({
      'id': 'rc1',
      'term': {'id': 't', 'name': 'Term 1'},
      'teacher_remark': 'Works hard.',
      'principal_remark': null,
      'snapshot': {
        'organization': {'name': 'Demo School'},
        'show_position': true,
        'page': {
          'student': {'id': 'user-1', 'full_name': 'Test Student'},
          'section': {'id': 'sa', 'name': 'A', 'class_name': 'Class 6'},
          'overall': _line(null, 84, 'A'),
          'subjects': [_line('Mathematics', 90, 'A+')],
          'position': 3,
          'class_size': 30,
          'attendance': {
            'counts': {'present': 40, 'late': 2, 'absent': 1, 'leave': 2},
          },
        },
      },
    }),
  );

Future<void> _open(
  WidgetTester tester,
  String route, {
  FakeApi? api,
  String? lang,
  Session? session,
}) async {
  final c = await pumpInstructorApp(
    tester,
    api: api ?? _api(),
    session: session ?? testSession(),
    prefs: {'language': ?lang},
  );
  c.read(routerProvider).go(route);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('marks: a result and an absence', (tester) async {
    await _open(tester, AppRoutes.marks);
    expect(find.text('Half-yearly'), findsOneWidget);
    expect(find.text('82/100 · 82% · (A)'), findsOneWidget);
    expect(find.text(_en.marksAbsent), findsOneWidget);
  });

  testWidgets('marks: none yet', (tester) async {
    await _open(tester, AppRoutes.marks, api: _api(empty: true));
    expect(find.text(_en.marksMyEmpty), findsOneWidget);
  });

  testWidgets('my performance: overall, parts, subjects, exams', (
    tester,
  ) async {
    await _open(tester, AppRoutes.performance);
    expect(find.text('84.3%'), findsOneWidget);
    expect(find.text(_en.performancePositionOf(3, 30)), findsOneWidget);
    expect(find.text('66.7%'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('perf-exams')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(PerformanceScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('A+'), findsOneWidget);
    expect(find.text('82/100'), findsOneWidget);
  });

  testWidgets('report cards: the list, then a card', (tester) async {
    await _open(tester, AppRoutes.reportCards);
    expect(find.text('Term 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('card-rc1')));
    await tester.pumpAndSettle();
    expect(find.byType(ReportCardScreen), findsOneWidget);
    expect(find.text('Demo School'), findsWidgets);
    expect(find.text(_en.reportCardPositionOf(3, 30)), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Works hard.'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ReportCardScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Works hard.'), findsOneWidget);
  });

  testWidgets('teachers get their sections (section_performance_test)', (
    tester,
  ) async {
    await _open(
      tester,
      AppRoutes.performance,
      session: Session.fromPayload({...sessionPayload(), 'role': 'TEACHER'}),
    );
    expect(find.byType(SectionPerformanceScreen), findsOneWidget);
    expect(find.text(_en.appNotYetBody), findsNothing);
  });

  testWidgets('in Bangla', (tester) async {
    final bn = AppLocalizationsBn();
    await _open(tester, AppRoutes.marks, lang: 'bn');
    expect(find.text(bn.marksMyTitle), findsWidgets);
  });
}

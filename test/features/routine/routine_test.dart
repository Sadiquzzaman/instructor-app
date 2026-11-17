import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/routine/data/routine.dart';
import 'package:instructor_app/features/routine/screens/routine_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Map<String, Object?> _slot(
  String id,
  String section,
  int day,
  String start, {
  String subject = 'Mathematics',
  String offering = 'o-math',
  Map<String, Object?>? teacher,
  String? room = 'Room 101',
}) => {
  'id': id,
  'session_id': 's',
  'section': {'id': section, 'name': 'A', 'class_name': 'Class 6'},
  'subject': {'offering_id': offering, 'id': 'sub', 'name': subject},
  'teacher': teacher,
  'room': room,
  'day_of_week': day,
  'start_time': start,
  'end_time': '${start.substring(0, 3)}45',
  'clashes': <Object>[],
};

Map<String, Object?> _routine({bool twoSections = false}) => {
  'session': {'id': 's', 'name': '2026', 'status': 'ACTIVE'},
  'can_manage': false,
  'editable_section_ids': <Object>[],
  'sections': [
    {'id': 'sa', 'name': 'A', 'class_name': 'Class 6'},
    if (twoSections) {'id': 'sb', 'name': 'B', 'class_name': 'Class 7'},
  ],
  'subject_classes': [
    {
      'offering_id': 'o-math',
      'section_id': 'sa',
      'subject': {'id': 'sub', 'name': 'Mathematics'},
      'teacher_ids': ['t1'],
    },
  ],
  'teachers': [
    {'id': 't1', 'full_name': 'Rina Akter'},
    {'id': 't2', 'full_name': 'Karim Uddin'},
  ],
  'rooms': ['Room 101'],
  'slots': [
    _slot('p2', 'sa', 6, '11:00'),
    _slot(
      'p1',
      'sa',
      6,
      '10:00',
      subject: 'English',
      offering: 'o-eng',
      teacher: {'id': 't2', 'full_name': 'Karim Uddin'},
    ),
    _slot('p3', 'sa', 2, '10:00', room: null),
    if (twoSections)
      _slot('p9', 'sb', 1, '09:00', subject: 'Physics', offering: 'x'),
  ],
};

FakeApi _api({FakeHandler? routine}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /calendar/me', (_) => ok({'items': <Object>[]}))
  ..on('GET /routine', routine ?? (_) => ok(_routine()));

Future<void> _open(
  WidgetTester tester,
  FakeApi api, {
  Map<String, Object> prefs = const {},
}) async {
  final c = await pumpInstructorApp(
    tester,
    api: api,
    session: testSession(),
    prefs: prefs,
  );
  c.read(routerProvider).go(AppRoutes.routine);
  await tester.pumpAndSettle();
}

Finder _inDay(int day, Finder f) =>
    find.descendant(of: find.byKey(Key('routine-day-$day')), matching: f);

void main() {
  test('periods in order; the subject\'s teacher when none is named', () {
    final r = Routine.fromJson(_routine());
    expect(r.sections, {'sa': 'Class 6 A'});
    expect(r.periods.map((p) => p.id), [
      'p3',
      'p1',
      'p2',
    ]); // Tue, then Sat by time
    expect(r.periods.firstWhere((p) => p.id == 'p1').teacher, 'Karim Uddin');
    expect(r.periods.firstWhere((p) => p.id == 'p2').teacher, 'Rina Akter');
  });

  testWidgets('the week, Saturday first, each period with who and where', (
    tester,
  ) async {
    await _open(tester, _api());
    expect(find.byType(RoutineScreen), findsOneWidget);
    expect(_inDay(6, find.text('English')), findsOneWidget);
    expect(_inDay(6, find.text('Karim Uddin · Room 101')), findsOneWidget);
    expect(_inDay(6, find.text('Rina Akter · Room 101')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('routine-day-3')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(RoutineScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(_inDay(3, find.text(_en.routineNoClasses)), findsOneWidget);
  });

  testWidgets('several sections: choose one', (tester) async {
    await _open(tester, _api(routine: (_) => ok(_routine(twoSections: true))));
    expect(find.text('Physics'), findsNothing);
    await tester.tap(find.byKey(const Key('routine-section')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Class 7 B').last);
    await tester.pumpAndSettle();
    expect(find.text('English'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Physics'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(RoutineScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Physics'), findsOneWidget);
  });

  testWidgets('offline: the saved week, marked as saved', (tester) async {
    await _open(
      tester,
      _api(
        routine: (r) => throw DioException.connectionError(
          requestOptions: RequestOptions(path: r.path),
          reason: 'offline',
        ),
      ),
      prefs: {
        'cache/user-1/organization/org-1/routine': jsonEncode({
          'saved_at': '2026-11-17T03:00:00.000Z',
          'payload': _routine(),
        }),
      },
    );
    expect(find.byKey(const Key('saved-copy')), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('a failed load can be retried; no sections says so', (
    tester,
  ) async {
    var calls = 0;
    await _open(
      tester,
      _api(
        routine: (_) => calls++ == 0
            ? apiError(500)
            : ok({'sections': <Object>[], 'slots': <Object>[]}),
      ),
    );
    expect(find.text(_en.routineLoadFailed), findsOneWidget);
    await tester.tap(find.text(_en.uiErrorRetry));
    await tester.pumpAndSettle();
    expect(find.byType(EmptyView), findsOneWidget);
  });

  testWidgets('in Bangla', (tester) async {
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), prefs: {'language': 'bn'});
    expect(find.text(bn.routineTitle), findsWidgets);
    expect(find.text(bn.routineDays6), findsOneWidget);
  });
}

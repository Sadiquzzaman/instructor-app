import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/classes/data/classes.dart';
import 'package:instructor_app/features/classes/screens/classes_screen.dart';
import 'package:instructor_app/features/classes/screens/teacher_classes_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

FakeApi _api({FakeHandler? list}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /calendar/me', (_) => ok({'items': <Object>[]}))
  ..on(
    'GET /student/classes',
    list ??
        (_) => ok([
          {
            'id': 'c1',
            'class_name': 'Class 6',
            'joined_at': '2026-11-07T13:46:56.452Z',
            'organization_name': 'Demo School',
            'context_label': 'Demo School',
          },
        ]),
  )
  ..on(
    'GET /student/classes/c1',
    (_) => ok({
      'id': 'c1',
      'class_name': 'Class 6',
      'description': null,
      'joined_at': '2026-11-07T13:46:56.452Z',
      'classmates': [
        {'name': 'Rahim Sarkar', 'joined_at': '2026-11-12T21:44:54.254Z'},
        {'name': 'Sumi Begum', 'joined_at': '2026-11-07T13:46:56.493Z'},
      ],
    }),
  )
  ..on('GET /student/classes/gone', (_) => apiError(403));

Future<void> _open(
  WidgetTester tester,
  FakeApi api,
  String route, {
  String? lang,
  Session? session,
}) async {
  final c = await pumpInstructorApp(
    tester,
    api: api,
    session: session ?? testSession(),
    prefs: {'language': ?lang},
  );
  c.read(routerProvider).go(route);
  await tester.pumpAndSettle();
}

void main() {
  test('a class and its classmates read the API answer', () {
    final d = ClassDetail.fromJson({
      'id': 'c1',
      'class_name': 'Class 6',
      'classmates': [
        {'name': 'A', 'joined_at': '2026-11-07T00:00:00Z'},
        {'joined_at': 'x'},
      ],
    })!;
    expect(d.classmates.single.name, 'A');
    expect(StudentClass.fromJson({'class_name': 'x'}), isNull);
    expect(AppRoutes.isAppPage('/classes/details/c1'), isTrue);
    expect(AppRoutes.isAppPage('/classes/create'), isFalse);
  });

  testWidgets('my classes; one opens with its classmates', (tester) async {
    await _open(tester, _api(), AppRoutes.classes);
    expect(find.text('Class 6'), findsOneWidget);
    expect(find.textContaining('Joined'), findsOneWidget);
    await tester.tap(find.byKey(const Key('class-c1')));
    await tester.pumpAndSettle();
    expect(find.byType(ClassDetailScreen), findsOneWidget);
    expect(find.text('Rahim Sarkar'), findsOneWidget);
    expect(find.text('Sumi Begum'), findsOneWidget);
  });

  testWidgets('no classes yet', (tester) async {
    await _open(tester, _api(list: (_) => ok(<Object>[])), AppRoutes.classes);
    // Level words ([[class]]) are the workspace's own; match the rest.
    expect(find.textContaining('invite link'), findsOneWidget);
  });

  testWidgets('a class the student is not in: not found, back', (tester) async {
    await _open(tester, _api(), '${AppRoutes.classes}/details/gone');
    expect(find.byType(ClassDetailScreen), findsOneWidget);
    await tester.tap(find.textContaining('Back to'));
    await tester.pumpAndSettle();
    expect(find.byType(ClassesScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('teachers get their own classes (teacher_classes_test)', (
    tester,
  ) async {
    await _open(
      tester,
      _api()..on('GET /classes', (_) => ok(<Object>[])),
      AppRoutes.classes,
      session: Session.fromPayload({...sessionPayload(), 'role': 'TEACHER'}),
    );
    expect(find.byType(TeacherClassesScreen), findsOneWidget);
    expect(find.text(_en.appNotYetBody), findsNothing);
  });

  testWidgets('in Bangla', (tester) async {
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), AppRoutes.classes, lang: 'bn');
    expect(find.text('Class 6'), findsOneWidget);
    expect(find.textContaining(bn.classesJoinedOn('').trim()), findsOneWidget);
  });
}

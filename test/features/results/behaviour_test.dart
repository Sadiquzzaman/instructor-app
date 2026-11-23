import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/features/results/screens/behaviour_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Session _teacher() =>
    Session.fromPayload({...sessionPayload(), 'role': 'TEACHER'});

Map<String, Object?> _grid({bool canEdit = true}) => {
  'offering': {
    'id': 'o1',
    'subject': {'id': 'm', 'name': 'Mathematics'},
    'section': {'id': 'sa', 'name': 'A', 'class_name': 'Class 6'},
  },
  'date': OrgTime.today(),
  'criteria': [
    {'id': 'k1', 'name_en': 'Discipline', 'name_bn': 'শৃঙ্খলা'},
    {'id': 'k2', 'name_en': 'Effort', 'name_bn': 'প্রচেষ্টা'},
  ],
  'rows': [
    {
      'student': {'id': 's1', 'full_name': 'Karim Hasan', 'roll_no': '1'},
      'ratings': {'k1': 4},
      'remark': null,
    },
    {
      'student': {'id': 's2', 'full_name': 'Nadia Islam', 'roll_no': '2'},
      'ratings': <String, int>{},
      'remark': null,
    },
  ],
  'can_edit': canEdit,
};

FakeApi _api({FakeHandler? grid, FakeHandler? save, List<Object>? classes}) =>
    FakeApi()
      ..on('GET /auth/contexts', (_) => ok(<Object>[]))
      ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
      ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
      ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
      ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
      ..on(
        'GET /offline-exams/subject-classes',
        (_) => ok(
          classes ??
              [
                {
                  'offering_id': 'o1',
                  'section_label': 'Class 6 A',
                  'subject': {'id': 'm', 'name': 'Mathematics'},
                  'terms': <Object>[],
                },
              ],
        ),
      )
      ..on('GET /behaviour/grid', grid ?? (_) => ok(_grid()))
      ..on('PUT /behaviour/grid', save ?? (_) => ok(_grid()));

Future<void> _open(WidgetTester tester, FakeApi api, {String? lang}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _teacher(),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go('/behaviour');
  await tester.pumpAndSettle();
}

Finder _scrollable() => find.byType(Scrollable).first;

/// Scrolls Save fully into view and taps it.
Future<void> _tapSave(WidgetTester tester) async {
  final save = find.byKey(const Key('behaviour-save'));
  await tester.scrollUntilVisible(save, 200, scrollable: _scrollable());
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a class and today: rate a student, save the changed one', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    expect(find.byType(BehaviourScreen), findsOneWidget);
    expect(api.to('GET /behaviour/grid').single.query, {
      'offering_id': 'o1',
      'date': OrgTime.today(),
    });
    expect(find.text('Discipline'), findsNWidgets(2));
    await tester.scrollUntilVisible(
      find.byKey(const Key('rating-s2-k2')),
      200,
      scrollable: _scrollable(),
    );
    await tester.tap(find.byKey(const Key('rating-s2-k2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('remark-s2')),
      ' Helped others ',
    );
    await tester.pump();
    expect(find.text(_en.behaviourUnsaved(1)), findsOneWidget);
    await _tapSave(tester);
    expect(api.to('PUT /behaviour/grid').single.body, {
      'offering_id': 'o1',
      'date': OrgTime.today(),
      'rows': [
        {
          'student_id': 's2',
          'ratings': {'k2': 5},
          'remark': 'Helped others',
        },
      ],
    });
    expect(find.text(_en.behaviourSaved), findsOneWidget);
  });

  testWidgets('a refusal in the web\'s words', (tester) async {
    await _open(
      tester,
      _api(save: (_) => apiError(400, code: 'RESULTS_REMARK_NEEDS_RATING')),
    );
    await tester.enterText(find.byKey(const Key('remark-s1')), 'Quiet');
    await tester.pump();
    await _tapSave(tester);
    expect(
      find.text(_en.behaviourErrorsRESULTSREMARKNEEDSRATING),
      findsOneWidget,
    );
  });

  testWidgets('read-only, and no classes', (tester) async {
    await _open(tester, _api(grid: (_) => ok(_grid(canEdit: false))));
    expect(find.text(_en.behaviourReadOnly), findsOneWidget);
    expect(find.byKey(const Key('behaviour-save')), findsNothing);
  });

  testWidgets('no subject classes says so', (tester) async {
    await _open(tester, _api(classes: []));
    expect(find.text(_en.behaviourNoClasses), findsOneWidget);
  });

  testWidgets('in Bangla: the criteria\'s Bangla names, on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.behaviourTitle), findsOneWidget);
    expect(find.text('শৃঙ্খলা'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

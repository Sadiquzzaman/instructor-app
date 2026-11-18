import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/results/screens/results_screens.dart';
import 'package:instructor_app/features/results/screens/staff_report_cards_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Session _teacher() =>
    Session.fromPayload({...sessionPayload(), 'role': 'TEACHER'});

Map<String, Object?> _cards({bool principal = false, bool made = false}) => {
  'section': {'id': 'sa', 'name': 'A'},
  'term': null,
  'can_write_principal_remark': principal,
  'rows': [
    {
      'student': {'id': 's1', 'full_name': 'Karim Hasan', 'roll_no': '1'},
      'latest': made
          ? {
              'id': 'rc1',
              'version': 2,
              'generated_at': '2026-11-01T04:00:00Z',
              'locale': 'bn',
              'teacher_remark': 'Works hard.',
              'principal_remark': 'Well done.',
              'share_expires_at': null,
            }
          : null,
    },
    {
      'student': {'id': 's2', 'full_name': 'Nadia Islam', 'roll_no': '2'},
      'latest': null,
    },
  ],
};

FakeApi _api({bool principal = false, bool made = false}) => FakeApi()
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
  ..on('GET /report-cards', (_) => ok(_cards(principal: principal, made: made)))
  ..on('POST /report-cards/generate', (_) => ok(_cards(made: true)))
  ..on('POST /report-cards/share', (_) => ok({'cards': 1, 'guardian_sms': 1}));

Future<void> _open(WidgetTester tester, FakeApi api, {String? lang}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _teacher(),
    prefs: {'language': ?lang},
  );
  app.read(routerProvider).go('/report-cards');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

Finder _scrollable() => find.byType(Scrollable).first;

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: _scrollable());
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('teachers get their sections, not the website', (tester) async {
    final api = _api();
    await _open(tester, api);
    expect(find.byType(StaffReportCardsScreen), findsOneWidget);
    expect(find.text(_en.appNotYetBody), findsNothing);
    expect(api.to('GET /report-cards').last.query['section_id'], 'sa');
    expect(find.text(_en.reportCardsMadeCount(0, 2)), findsOneWidget);
    // Teachers don't write the principal's remark.
    expect(find.byKey(const Key('principal-remark-s1')), findsNothing);
    expect(find.text(_en.reportCardsPrincipalLater), findsWidgets);
    // Nothing made yet: nothing to share.
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('cards-share')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('Make cards sends the remarks and the language', (tester) async {
    final api = _api();
    await _open(tester, api);
    await tester.enterText(
      find.byKey(const Key('teacher-remark-s1')),
      'Works hard.',
    );
    await _tap(tester, find.byKey(const Key('cards-make')));
    final body = api.to('POST /report-cards/generate').single.body as Map;
    expect(body['section_id'], 'sa');
    expect(body['locale'], 'en');
    expect(body.containsKey('term_id'), isFalse);
    final rows = body['rows'] as List;
    expect(rows.first, {'student_id': 's1', 'teacher_remark': 'Works hard.'});
    expect(find.text(_en.reportCardsMadeToast(1)), findsOneWidget);
    expect(find.text(_en.reportCardsMadeCount(1, 2)), findsOneWidget);
  });

  testWidgets('a term asks for that term', (tester) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('cards-term')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Term 1').last);
    await tester.pumpAndSettle();
    expect(api.to('GET /report-cards').last.query['term_id'], 't1');
  });

  testWidgets('owners write the principal remark', (tester) async {
    final api = _api(principal: true, made: true);
    await _open(tester, api);
    expect(find.byKey(const Key('principal-remark-s1')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('cards-make')));
    final rows =
        (api.to('POST /report-cards/generate').single.body as Map)['rows']
            as List;
    expect((rows.first as Map)['principal_remark'], 'Well done.');
  });

  testWidgets('Share asks first, then shares', (tester) async {
    final api = _api(made: true);
    await _open(tester, api);
    await _tap(tester, find.byKey(const Key('cards-share')));
    expect(find.text(_en.reportCardsShareDetail(1)), findsOneWidget);
    // Cancel sends nothing.
    await tester.tap(find.text(_en.uiCancel));
    await tester.pumpAndSettle();
    expect(api.to('POST /report-cards/share'), isEmpty);
    await _tap(tester, find.byKey(const Key('cards-share')));
    await tester.tap(find.byKey(const Key('share-confirm')));
    await tester.pumpAndSettle();
    expect(
      (api.to('POST /report-cards/share').single.body as Map)['section_id'],
      'sa',
    );
    expect(find.textContaining(_en.reportCardsSharedToast(1)), findsOneWidget);
  });

  testWidgets('a made card opens', (tester) async {
    final api = _api(made: true)
      ..on(
        'GET /report-cards/rc1',
        (_) => ok({
          'id': 'rc1',
          'version': 2,
          'locale': 'bn',
          'payload': <String, Object?>{},
        }),
      );
    await _open(tester, api);
    await _tap(tester, find.byKey(const Key('card-open-s1')));
    expect(find.byType(ReportCardScreen), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(made: true), lang: 'bn');
    expect(find.text(bn.reportCardsTitle), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

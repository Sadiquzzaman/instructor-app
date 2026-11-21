import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/ielts/data/profiles.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';
import 'ielts_overview_test.dart' show ieltsMember;

final _en = AppLocalizationsEn();

Map<String, Object?> _profile({
  String id = 's1',
  String? type = 'ACADEMIC',
  num? overall = 7,
}) => {
  'student': {'id': id, 'full_name': 'Tania Akter', 'batch': 'Evening A'},
  'test_type': type,
  'target_overall': overall,
  'target_bands': {'WRITING': 6.5, 'SPEAKING': 7},
  'test_date': '2026-12-20',
  'days_to_test': 29,
};

FakeApi _api({FakeHandler? me}) => FakeApi()
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
    'GET /sections',
    (_) => ok([
      {'id': 'sa', 'name': 'A', 'class_id': 'k1'},
    ]),
  )
  ..on(
    'GET /classes',
    (_) => ok([
      {'id': 'k1', 'class_name': 'Evening'},
    ]),
  )
  ..on('GET /ielts/profiles', (_) => ok([_profile()]))
  ..on('PUT /ielts/profiles/s1', (r) => ok(r.body))
  ..on('GET /ielts/profiles/me', me ?? (_) => ok(_profile()));

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
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  test('targets are 0 to 9 in half bands; the body sends every field', () {
    expect(ieltsBands.first, 0);
    expect(ieltsBands.last, 9);
    expect(ieltsBands, hasLength(19));
    expect(profileBody(testType: 'GENERAL', targets: {'READING': 6.5}), {
      'test_type': 'GENERAL',
      'target_overall': null,
      'target_bands': {
        'LISTENING': null,
        'READING': 6.5,
        'WRITING': null,
        'SPEAKING': null,
      },
      'test_date': null,
    });
  });

  testWidgets('staff: students with targets; set a profile', (tester) async {
    final api = _api();
    await _open(tester, api, 'TEACHER', '/ielts/students');
    expect(find.text('Tania Akter'), findsOneWidget);
    expect(find.textContaining('Evening A · Academic'), findsOneWidget);
    expect(find.textContaining('— / — / 6.5 / 7.0'), findsOneWidget);
    expect(find.textContaining(_en.ieltsDaysLeft(29)), findsOneWidget);

    await _tap(tester, find.byKey(const Key('ielts-edit-s1')));
    await _tap(tester, find.text(_en.ieltsTypesGENERAL));
    await _tap(tester, find.byKey(const Key('ielts-target-LISTENING')));
    await tester.tap(find.text('1.0').last);
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('ielts-profile-save')));

    final body = api.to('PUT /ielts/profiles/s1').single.body! as Map;
    expect(body['test_type'], 'GENERAL');
    expect(body['target_overall'], 7);
    expect(body['target_bands'], {
      'LISTENING': 1,
      'READING': null,
      'WRITING': 6.5,
      'SPEAKING': 7,
    });
    expect(body['test_date'], '2026-12-20');
  });

  testWidgets('a batch narrows the list', (tester) async {
    final api = _api();
    await _open(tester, api, 'ADMIN', '/ielts/students');
    await _tap(tester, find.byKey(const Key('ielts-batch')));
    await tester.tap(find.text('Evening A').last);
    await tester.pumpAndSettle();
    expect(api.to('GET /ielts/profiles').last.query['section_id'], 'sa');
  });

  testWidgets('a student: my targets and the countdown', (tester) async {
    await _open(tester, _api(), 'STUDENT', '/ielts/me');
    expect(find.text(_en.ieltsMyTitle), findsWidgets);
    expect(find.text('7.0'), findsWidgets);
    expect(find.text(_en.ieltsDaysLeft(29)), findsOneWidget);
  });

  testWidgets('a student with no profile yet', (tester) async {
    await _open(
      tester,
      _api(
        me: (_) => ok({
          'student': {'id': 's1'},
          'test_type': null,
          'target_overall': null,
          'target_bands': <String, Object>{},
          'test_date': null,
          'days_to_test': null,
        }),
      ),
      'STUDENT',
      '/ielts/me',
    );
    expect(find.byKey(const Key('ielts-no-profile')), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), 'OWNER', '/ielts/students', lang: 'bn');
    expect(find.text(bn.ieltsStudentsTitle), findsWidgets);
    expect(tester.takeException(), isNull);
    await _tap(tester, find.byKey(const Key('ielts-edit-s1')));
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/location/locator.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/organization/screens/branches_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

class _Here implements Locator {
  @override
  Future<LocationFix> currentFix() async =>
      (latitude: 23.7577123, longitude: 90.3897456, accuracy: 12.4);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Session _member(String role) {
  final p = sessionPayload();
  return Session.fromPayload({
    ...p,
    'role': 'TEACHER',
    'organization': <String, dynamic>{
      ...(p['organization'] as Map<String, dynamic>),
      'role': role,
    },
  });
}

FakeApi _api({FakeHandler? remove}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /attendance/branches',
    (_) => ok([
      {
        'id': 'b1',
        'name': null,
        'address': 'Dhanmondi 27',
        'geo_lat': 23.75,
        'geo_lng': 90.38,
        'checkin_radius_m': 150,
        'is_default': true,
        'section_count': 4,
      },
      {
        'id': 'b2',
        'name': 'Uttara',
        'address': null,
        'geo_lat': null,
        'geo_lng': null,
        'checkin_radius_m': 100,
        'is_default': false,
        'section_count': 1,
      },
    ]),
  )
  ..on('POST /attendance/branches', (_) => ok({'id': 'b3'}))
  ..on('PATCH /attendance/branches/b2', (_) => ok({'id': 'b2'}))
  ..on('DELETE /attendance/branches/b2', remove ?? (_) => ok(null));

Future<List<Uri>> _open(
  WidgetTester tester,
  FakeApi api, {
  String role = 'OWNER',
  String? lang,
}) async {
  final links = <Uri>[];
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: _member(role),
    prefs: {'language': ?lang},
    openedLinks: links,
    overrides: [locatorProvider.overrideWithValue(_Here())],
  );
  app.read(routerProvider).go('/attendance-branches');
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
  return links;
}

/// The list of the page on top: the form when it is open.
Finder _page() {
  final form = find.byType(BranchFormScreen);
  return find
      .descendant(
        of: form.evaluate().isEmpty ? find.byType(BranchesScreen) : form,
        matching: find.byType(Scrollable),
      )
      .first;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 200, scrollable: _page());
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('reading a pin as the web does', () {
    test('a Google Maps place, centre, query and plain text', () {
      expect(
        pinFromText(
          'https://www.google.com/maps/place/X/@23.7,90.3,17z/data=!3d23.7577!4d90.3897',
        ),
        (lat: 23.7577, lng: 90.3897),
      );
      expect(pinFromText('https://www.google.com/maps/@23.7577,90.3897,17z'), (
        lat: 23.7577,
        lng: 90.3897,
      ));
      expect(pinFromText('https://maps.google.com/?q=23.7577%2C90.3897'), (
        lat: 23.7577,
        lng: 90.3897,
      ));
      expect(pinFromText(' 23.7577123, 90.3897456 '), (
        lat: 23.757712,
        lng: 90.389746,
      ));
      expect(
        pinFromText('https://www.openstreetmap.org/#map=17/23.7577/90.3897'),
        (lat: 23.7577, lng: 90.3897),
      );
    });

    test('short links and nonsense give nothing', () {
      expect(pinFromText('https://maps.app.goo.gl/abc'), isNull);
      expect(pinFromText('95, 200'), isNull);
      expect(pinFromText(''), isNull);
    });

    test('problems: half a pin, out of range, the radius', () {
      expect(locationProblems('23.7', '', '100').lng, 'pinIncomplete');
      expect(locationProblems('', '90.3', '100').lat, 'pinIncomplete');
      expect(locationProblems('91', '90', '100').lat, 'latInvalid');
      expect(locationProblems('', '', '20').radius, 'radiusInvalid');
      expect(locationProblems('', '', '1001').radius, 'radiusInvalid');
      expect(locationProblems('23.7', '90.3', '150'), (
        lat: null,
        lng: null,
        radius: null,
      ));
    });
  });

  testWidgets('branches: the main one stays; pin or no pin', (tester) async {
    await _open(tester, _api());
    expect(find.text(_en.branchesMainBranch), findsOneWidget);
    expect(find.text(_en.branchesMain), findsOneWidget);
    expect(find.text(_en.branchesRadiusShort('150')), findsOneWidget);
    expect(find.text(_en.branchesNoPin), findsOneWidget);
    expect(find.byKey(const Key('branch-remove-b1')), findsNothing);
    expect(find.byKey(const Key('branch-remove-b2')), findsOneWidget);
  });

  testWidgets('add a branch from a pasted link; check it on Google Maps', (
    tester,
  ) async {
    final api = _api();
    final links = await _open(tester, api);
    await tester.tap(find.byKey(const Key('branch-add')));
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('branch-save'));
    await tester.scrollUntilVisible(save, 200, scrollable: _page());
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('branch-name')),
      -200,
      scrollable: _page(),
    );
    await tester.enterText(find.byKey(const Key('branch-name')), ' Mirpur ');
    await tester.enterText(
      find.byKey(const Key('branch-link')),
      'https://www.google.com/maps/@23.8069,90.3687,17z',
    );
    await tester.pump();
    await _tap(tester, find.byKey(const Key('branch-check')));
    expect(links.single.queryParameters['q'], '23.8069,90.3687');
    await _tap(tester, save);
    expect(api.to('POST /attendance/branches').single.body, {
      'name': 'Mirpur',
      'address': null,
      'geo_lat': 23.8069,
      'geo_lng': 90.3687,
      'checkin_radius_m': 150,
    });
  });

  testWidgets('use this phone\'s location', (tester) async {
    final api = _api();
    await _open(tester, api);
    await _tap(tester, find.byKey(const Key('branch-edit-b2')));
    await _tap(tester, find.byKey(const Key('branch-use-mine')));
    expect(find.text(_en.branchesLocationLocated('12')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('branch-save')));
    final body = api.to('PATCH /attendance/branches/b2').single.body! as Map;
    expect(body['geo_lat'], 23.757712);
    expect(body['geo_lng'], 90.389746);
  });

  testWidgets('a branch in use is not removed; says why', (tester) async {
    final api = _api(
      remove: (_) => apiError(409, code: 'ATTENDANCE_BRANCH_IN_USE'),
    );
    await _open(tester, api);
    await _tap(tester, find.byKey(const Key('branch-remove-b2')));
    expect(find.textContaining('Uttara will no longer'), findsOneWidget);
    await tester.tap(find.byKey(const Key('branch-remove-confirm')));
    await tester.pumpAndSettle();
    expect(find.text(_en.branchesErrorsATTENDANCEBRANCHINUSE), findsOneWidget);
  });

  testWidgets('teachers read only', (tester) async {
    await _open(tester, _api(), role: 'TEACHER');
    expect(find.byKey(const Key('branch-add')), findsNothing);
    expect(find.byKey(const Key('branch-edit-b1')), findsNothing);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.branchesTitle), findsOneWidget);
    await tester.tap(find.byKey(const Key('branch-add')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

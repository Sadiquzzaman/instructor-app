import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/resources/resources_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

Map<String, Object?> _res(String id, String type, {bool isNew = false}) => {
  'id': id,
  'type': type,
  'title': type == 'LINK' ? 'Khan Academy fractions' : 'Chapter 3 notes',
  'description': null,
  'subject': {'id': 'm', 'name': 'Mathematics'},
  'folder_id': null,
  'tags': <String>[],
  'download_allowed': type != 'FILE',
  'archived': false,
  'url': type == 'LINK'
      ? 'https://www.khanacademy.org/x'
      : '/api/v1/files/f1/content',
  'file': type == 'FILE'
      ? {'name': 'notes.pdf', 'mime': 'application/pdf', 'size': 10}
      : null,
  'shares': <Object>[],
  'created_by': {'id': 't', 'name': 'Rina Akter'},
  'created_at': '2026-11-10T00:00:00Z',
  'is_new': isNew,
};

FakeApi _api({FakeHandler? mine}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /calendar/me', (_) => ok({'items': <Object>[]}))
  ..on(
    'GET /resources/mine',
    mine ??
        (r) => ok([
          if (r.query['type'] != 'LINK') _res('r1', 'FILE', isNew: true),
          if (r.query['type'] != 'FILE') _res('r2', 'LINK'),
        ]),
  )
  ..on('POST /resources/r1/open', (_) => ok(null))
  ..on('POST /resources/r2/open', (_) => ok(null));

Future<(FakeApi, List<Uri>)> _open(WidgetTester tester, {FakeApi? api}) async {
  final links = <Uri>[];
  final a = api ?? _api();
  final c = await pumpInstructorApp(
    tester,
    api: a,
    session: testSession(),
    openedLinks: links,
  );
  c.read(routerProvider).go(AppRoutes.resources);
  await tester.pumpAndSettle();
  return (a, links);
}

void main() {
  test('a file opens through the API host; a link as it is', () {
    final f = Resource.fromJson(_res('r1', 'FILE'))!;
    expect(f.target.path, '/api/v1/files/f1/content');
    final l = Resource.fromJson(_res('r2', 'LINK'))!;
    expect(l.target.toString(), 'https://www.khanacademy.org/x');
  });

  testWidgets('shared resources; opening one is recorded, then it opens', (
    tester,
  ) async {
    final (api, links) = await _open(tester);
    expect(find.text('Chapter 3 notes'), findsOneWidget);
    expect(find.text(_en.resourcesNew), findsOneWidget);
    expect(find.text(_en.resourcesViewOnlyNote), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('resource-r1')),
        matching: find.text(_en.resourcesOpen),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.to('POST /resources/r1/open'), hasLength(1));
    expect(links.single.path, '/api/v1/files/f1/content');
    expect(find.text(_en.resourcesNew), findsNothing);
  });

  testWidgets('filter by type', (tester) async {
    final (api, _) = await _open(tester);
    await tester.tap(find.byKey(const Key('resource-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.resourcesTypesLINK).last);
    await tester.pumpAndSettle();
    expect(api.to('GET /resources/mine').last.query['type'], 'LINK');
    expect(find.text('Chapter 3 notes'), findsNothing);
    expect(find.text('Khan Academy fractions'), findsOneWidget);
  });

  testWidgets('search waits for typing to stop', (tester) async {
    final (api, _) = await _open(tester);
    await tester.enterText(find.byKey(const Key('resource-search')), 'frac');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(api.to('GET /resources/mine').last.query['q'], 'frac');
  });

  testWidgets('not in the plan: says so', (tester) async {
    await _open(
      tester,
      api: _api(mine: (_) => apiError(403, code: 'FEATURE_NOT_IN_PLAN')),
    );
    expect(find.text(_en.resourcesNotAvailable), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/files/file_picking.dart';
import 'package:instructor_app/core/files/local_file.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/resources/staff_resources_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

class _Picking implements FilePicking {
  @override
  Future<LocalFile?> takePhoto() async => LocalFile.bytes('board.jpg', [1, 2]);
  @override
  Future<List<LocalFile>> choosePhotos({int? limit}) async => [
    LocalFile.bytes('board.jpg', [1, 2]),
  ];
  @override
  Future<List<LocalFile>> chooseFiles(List<String> extensions) async => [];
}

Map<String, Object?> _res({bool archived = false, bool canEdit = true}) => {
  'id': 'r1',
  'type': 'FILE',
  'title': 'Chapter 3 notes',
  'description': 'Fractions',
  'subject': {'id': 'm', 'name': 'Mathematics'},
  'folder_id': null,
  'tags': ['fractions'],
  'download_allowed': false,
  'archived': archived,
  'url': '/files/f9/content',
  'file': {'name': 'notes.pdf', 'mime': 'application/pdf', 'size': 10},
  'shares': [
    {'offering_id': 'o1', 'label': 'Class 6 A · Mathematics'},
  ],
  'created_by': {'id': 't', 'name': 'Rina Akter'},
  'created_at': '2026-11-10T00:00:00Z',
  'can_edit': canEdit,
};

FakeApi _api({bool canEdit = true}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on(
    'GET /resources',
    (r) =>
        ok([_res(archived: r.query['archived'] == 'true', canEdit: canEdit)]),
  )
  ..on(
    'GET /resources/subject-classes',
    (_) => ok([
      {
        'offering_id': 'o1',
        'label': 'Class 6 A · Mathematics',
        'subject': {'id': 'm', 'name': 'Mathematics'},
      },
      {
        'offering_id': 'o2',
        'label': 'Class 6 B · Mathematics',
        'subject': {'id': 'm', 'name': 'Mathematics'},
      },
    ]),
  )
  ..on(
    'GET /resources/folders',
    (_) => ok([
      {'id': 'fo1', 'name': 'Term 1'},
    ]),
  )
  ..on('POST /resources/folders', (_) => ok({'id': 'fo2', 'name': 'Revision'}))
  ..on('DELETE /resources/folders/fo1', (_) => ok(null))
  ..on('POST /resources', (_) => ok(_res()))
  ..on('PATCH /resources/r1', (_) => ok(_res()))
  ..on('DELETE /resources/r1', (_) => ok(null))
  ..on(
    'GET /resources/r1/insights',
    (_) => ok({
      'students': 2,
      'opened': [
        {
          'student_id': 's1',
          'full_name': 'Karim Hasan',
          'via': 'Class 6 A · Mathematics',
          'first_opened_at': '2026-11-14T05:00:00Z',
          'last_opened_at': '2026-11-14T05:00:00Z',
          'opens': 2,
        },
      ],
      'not_opened': [
        {
          'student_id': 's2',
          'full_name': 'Nadia Islam',
          'via': 'Class 6 A · Mathematics',
        },
      ],
    }),
  )
  ..on(
    'POST /files/presign',
    (_) => ok({
      'file': {'id': 'f1'},
      'upload': {
        'url': 'https://storage.test/b/f1',
        'headers': {'Content-Type': 'image/jpeg'},
      },
      'storage': {'warning': false},
    }),
  )
  ..on('PUT /b/f1', (_) => (200, null))
  ..on(
    'POST /files/f1/complete',
    (_) => ok({'id': 'f1', 'name': 'board.jpg', 'mime': 'image/jpeg'}),
  );

Future<void> _open(WidgetTester tester, FakeApi api, {String? lang}) async {
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: Session.fromPayload({...sessionPayload(), 'role': 'TEACHER'}),
    prefs: {'language': ?lang},
    overrides: [filePickingProvider.overrideWithValue(_Picking())],
  );
  app.read(routerProvider).go(AppRoutes.resources);
  await tester.pumpAndSettle();
  await tester.pump(Duration.zero);
  await tester.pumpAndSettle();
}

/// The list of the page on top: the form when it is open.
Finder _page(WidgetTester tester) {
  final form = find.byType(ResourceFormScreen);
  return find
      .descendant(
        of: form.evaluate().isEmpty ? find.byType(StaffResourcesScreen) : form,
        matching: find.byType(Scrollable),
      )
      .first;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: _page(tester));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final f = find.byKey(Key(key));
  await tester.scrollUntilVisible(f, 200, scrollable: _page(tester));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.enterText(f, value);
  await tester.pump();
}

void main() {
  testWidgets('teachers get their library, not the website', (tester) async {
    await _open(tester, _api());
    expect(find.byType(StaffResourcesScreen), findsOneWidget);
    expect(find.text(_en.appNotYetBody), findsNothing);
    expect(find.text('Chapter 3 notes'), findsOneWidget);
    expect(find.text(_en.resourcesViewOnly), findsOneWidget);
    expect(
      find.text(_en.resourcesSharedWith('Class 6 A · Mathematics')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('edit-r1')), findsOneWidget);
  });

  testWidgets("others' resources: open only", (tester) async {
    await _open(tester, _api(canEdit: false));
    expect(find.byKey(const Key('open-r1')), findsOneWidget);
    expect(find.byKey(const Key('edit-r1')), findsNothing);
    expect(find.byKey(const Key('delete-r1')), findsNothing);
  });

  testWidgets('add a link shared with a class', (tester) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('resource-add')));
    await tester.pumpAndSettle();
    expect(find.text(_en.resourcesAddTitle), findsOneWidget);
    await tester.tap(find.byKey(const Key('kind-link')));
    await tester.pumpAndSettle();
    await _enter(tester, 'resource-url', 'https://www.khanacademy.org/x');
    await _enter(tester, 'resource-title', '  Fractions video  ');
    await _enter(tester, 'resource-tags', 'fractions, revision, fractions');
    await _tap(tester, find.byKey(const Key('share-o2')));
    await _tap(tester, find.byKey(const Key('resource-save')));
    expect(api.to('POST /resources').single.body, {
      'type': 'LINK',
      'title': 'Fractions video',
      'tags': ['fractions', 'revision'],
      'download_allowed': true,
      'offering_ids': ['o2'],
      'url': 'https://www.khanacademy.org/x',
    });
    expect(find.byType(StaffResourcesScreen), findsOneWidget);
    expect(find.text(_en.resourcesSaved), findsOneWidget);
  });

  testWidgets('add a file: uploaded for resources, title from its name', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('resource-add')));
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('resource-save'));
    await tester.scrollUntilVisible(save, 200, scrollable: _page(tester));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('attach')),
      -200,
      scrollable: _page(tester),
    );
    await _tap(tester, find.byKey(const Key('attach')));
    await tester.tap(find.text(_en.appAttachChoosePhotos));
    await tester.pumpAndSettle();
    expect(
      (api.to('POST /files/presign').single.body as Map)['purpose'],
      'RESOURCE',
    );
    await _tap(tester, save);
    final body = api.to('POST /resources').single.body as Map;
    expect(body['type'], 'FILE');
    expect(body['file_id'], 'f1');
    expect(body['title'], 'board');
  });

  testWidgets('edit sends every field', (tester) async {
    final api = _api();
    await _open(tester, api);
    await _tap(tester, find.byKey(const Key('edit-r1')));
    expect(find.text(_en.resourcesEditTitle), findsOneWidget);
    expect(find.byKey(const Key('resource-url')), findsNothing);
    await _enter(tester, 'resource-title', 'Chapter 3, revised');
    await _tap(tester, find.byKey(const Key('resource-save')));
    expect(api.to('PATCH /resources/r1').single.body, {
      'title': 'Chapter 3, revised',
      'description': 'Fractions',
      'subject_id': 'm',
      'folder_id': null,
      'tags': ['fractions'],
      'download_allowed': false,
      'offering_ids': ['o1'],
    });
  });

  testWidgets('archive; delete asks first', (tester) async {
    final api = _api();
    await _open(tester, api);
    await _tap(tester, find.byKey(const Key('archive-r1')));
    expect(api.to('PATCH /resources/r1').single.body, {'archived': true});
    expect(find.text(_en.resourcesArchivedDone), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('delete-r1')));
    expect(find.text(_en.resourcesDeleteDetail), findsOneWidget);
    await tester.tap(find.text(_en.resourcesCancel));
    await tester.pumpAndSettle();
    expect(api.to('DELETE /resources/r1'), isEmpty);
    await _tap(tester, find.byKey(const Key('delete-r1')));
    await tester.tap(find.byKey(const Key('resource-delete-confirm')));
    await tester.pumpAndSettle();
    expect(api.to('DELETE /resources/r1'), hasLength(1));
  });

  testWidgets('archived and folders filter; add and delete a folder', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('resource-archived')));
    await tester.pumpAndSettle();
    expect(api.to('GET /resources').last.query['archived'], 'true');
    expect(find.text(_en.resourcesRestore), findsOneWidget);

    await tester.tap(find.byKey(const Key('resource-folder')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Term 1').last);
    await tester.pumpAndSettle();
    expect(api.to('GET /resources').last.query['folder_id'], 'fo1');
    await tester.tap(find.byKey(const Key('folder-delete')));
    await tester.pumpAndSettle();
    expect(api.to('DELETE /resources/folders/fo1'), hasLength(1));
    expect(api.to('GET /resources').last.query['folder_id'], isNull);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('folder-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('folder-name')), ' Revision ');
    await tester.tap(find.byKey(const Key('folder-save')));
    await tester.pumpAndSettle();
    expect(api.to('POST /resources/folders').single.body, {'name': 'Revision'});
  });

  testWidgets('who opened it', (tester) async {
    await _open(tester, _api());
    await _tap(tester, find.byKey(const Key('insights-r1')));
    expect(find.text(_en.resourcesOpenedCount(1, 2)), findsOneWidget);
    expect(find.text('Karim Hasan'), findsOneWidget);
    expect(find.text('Nadia Islam'), findsOneWidget);
  });

  testWidgets('a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bn = AppLocalizationsBn();
    final api = _api();
    await _open(tester, api, lang: 'bn');
    expect(find.text(bn.resourcesTitle), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('resource-add')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

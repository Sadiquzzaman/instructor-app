import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/auth/session_holder.dart';
import 'package:instructor_app/core/files/attachment_field.dart';
import 'package:instructor_app/core/files/file_picking.dart';
import 'package:instructor_app/core/files/file_uploader.dart';
import 'package:instructor_app/core/files/local_file.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

/// The answer of `POST /files/presign` for a file with [id].
Object _presigned(String id, {bool warning = false}) => {
  'file': {'id': id, 'status': 'PENDING'},
  'upload': {
    'url': 'https://storage.test/bucket/$id?X-Amz-Signature=abc',
    'method': 'PUT',
    'headers': {'Content-Type': 'image/jpeg'},
  },
  'storage': {'warning': warning, 'percent': warning ? 92 : 10},
};

FakeApi _api({FakeHandler? presign}) {
  var n = 0;
  return FakeApi()
    ..on('POST /files/presign', presign ?? (_) => ok(_presigned('f${++n}')))
    ..on('PUT /bucket/f1', (_) => (200, null))
    ..on('PUT /bucket/f2', (_) => (200, null))
    ..on(
      'POST /files/f1/complete',
      (_) => ok({
        'id': 'f1',
        'name': 'page.jpg',
        'mime': 'image/jpeg',
        'size_bytes': 900,
      }),
    )
    ..on('POST /files/f2/complete', (_) => ok({'id': 'f2'}));
}

Future<ApiClient> _client(FakeApi api) async {
  final sessions = SessionHolder(MemorySessionStore(testSession()));
  await sessions.restore();
  return ApiClient(
    baseUrl: 'https://api.test/api/v1',
    sessions: sessions,
    device: () async => testDevice,
    onSessionExpired: sessions.clear,
    adapter: api,
  );
}

class _FakePicking implements FilePicking {
  List<LocalFile> photos = [];
  List<LocalFile> files = [];
  List<String>? askedExtensions;

  @override
  Future<LocalFile?> takePhoto() async => photos.firstOrNull;

  @override
  Future<List<LocalFile>> choosePhotos({int? limit}) async => photos;

  @override
  Future<List<LocalFile>> chooseFiles(List<String> extensions) async {
    askedExtensions = extensions;
    return files;
  }
}

void main() {
  group('the upload', () {
    test('presign, PUT to the signed link, complete', () async {
      final api = _api();
      final progress = <double>[];
      final uploaded = await FileUploader(await _client(api)).upload(
        FilePurpose.leave,
        LocalFile.bytes('page.jpg', List.filled(1000, 1)),
        onProgress: progress.add,
      );
      expect(api.to('POST /files/presign').single.body, {
        'purpose': 'LEAVE',
        'mime': 'image/jpeg',
        'size': 1000,
        'name': 'page.jpg',
      });
      final put = api.to('PUT /bucket/f1').single;
      // The signed link gets only its own headers: no session, no workspace.
      expect(put.bearer, isNull);
      expect(put.organizationHeader, isNull);
      expect(
        put.headers['content-type'] ?? put.headers['Content-Type'],
        'image/jpeg',
      );
      expect(api.to('POST /files/f1/complete'), hasLength(1));
      expect(uploaded.id, 'f1');
      expect(uploaded.size, 900); // after the server's compression
      expect(uploaded.isImage, isTrue);
      expect(uploaded.storageWarning, isFalse);
    });

    test(
      'a discussion file names its class; the quota warning comes back',
      () async {
        final api = _api(presign: (_) => ok(_presigned('f1', warning: true)));
        final uploaded = await FileUploader(await _client(api)).upload(
          FilePurpose.discussion,
          LocalFile.bytes('notes.pdf', [1, 2, 3]),
          scopeId: 'class-1',
        );
        expect(
          (api.to('POST /files/presign').single.body! as Map)['scope_id'],
          'class-1',
        );
        expect(uploaded.storageWarning, isTrue);
      },
    );

    test('over the storage quota: PLAN_LIMIT_REACHED, nothing sent', () async {
      final api = _api(
        presign: (_) => apiError(403, code: 'PLAN_LIMIT_REACHED'),
      );
      await expectLater(
        FileUploader(await _client(api))
            .upload(FilePurpose.leave, LocalFile.bytes('a.jpg', [1])),
        throwsA(
          isA<ApiException>().having((e) => e.isPlanLimit, 'limit', true),
        ),
      );
      expect(api.requests.where((r) => r.method == 'PUT'), isEmpty);
    });

    test('types per purpose follow the server', () {
      expect(mimeForName('Scan.PDF'), 'application/pdf');
      expect(mimeForName('photo'), '');
      expect(FilePurpose.leave.allows('application/pdf'), isTrue);
      expect(FilePurpose.leave.allows(mimeForName('a.docx')), isFalse);
      expect(FilePurpose.exam.allowsDocuments, isFalse);
      expect(extensionsFor(FilePurpose.leave.mimes), contains('pdf'));
      expect(extensionsFor(FilePurpose.leave.mimes), isNot(contains('docx')));
      expect(fileContentUri('f1').toString(), endsWith('/files/f1/content'));
    });
  });

  group('the attachment field', () {
    late List<List<UploadedFile>> changes;
    late List<bool> busy;

    Future<_FakePicking> pump(
      WidgetTester tester,
      FakeApi api, {
      FilePurpose purpose = FilePurpose.leave,
      int maxFiles = 10,
    }) async {
      changes = [];
      busy = [];
      final picking = _FakePicking();
      final client = await _client(api);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            filePickingProvider.overrideWithValue(picking),
          ],
          child: inLanguage(
            AttachmentField(
              label: 'Attachment (optional)',
              purpose: purpose,
              maxFiles: maxFiles,
              onChanged: changes.add,
              onBusyChanged: busy.add,
            ),
          ),
        ),
      );
      return picking;
    }

    Future<void> choose(WidgetTester tester, String option) async {
      await tester.tap(find.byKey(const Key('attach')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option));
      await tester.pumpAndSettle();
    }

    testWidgets('chosen photos upload and are handed to the form', (
      tester,
    ) async {
      final picking = await pump(tester, _api());
      picking.photos = [
        LocalFile.bytes('page.jpg', [1, 2]),
        LocalFile.bytes('page2.png', [3]),
      ];
      await choose(tester, _en.appAttachChoosePhotos);
      expect(changes.last.map((f) => f.id), ['f1', 'f2']);
      expect(busy.last, isFalse);
      expect(find.text('page.jpg'), findsOneWidget);
      // Removing one tells the form.
      await tester.tap(find.byTooltip(_en.uiFileDropRemove('page.jpg')));
      await tester.pump();
      expect(changes.last.map((f) => f.id), ['f2']);
    });

    testWidgets('a type the purpose does not take is refused, not sent', (
      tester,
    ) async {
      final api = _api();
      final picking = await pump(tester, api);
      picking.files = [
        LocalFile.bytes('essay.docx', [1]),
      ];
      await choose(tester, _en.appAttachChooseFile);
      expect(picking.askedExtensions, containsAll(['pdf', 'jpg']));
      expect(
        find.text(_en.appAttachTypeNotAllowed('essay.docx')),
        findsOneWidget,
      );
      expect(api.to('POST /files/presign'), isEmpty);
    });

    testWidgets('a file over 20 MB is refused', (tester) async {
      final api = _api();
      final picking = await pump(tester, api);
      picking.photos = [
        LocalFile(
          name: 'huge.jpg',
          size: maxUploadBytes + 1,
          mime: 'image/jpeg',
          open: () => const Stream.empty(),
        ),
      ];
      await choose(tester, _en.appAttachChoosePhotos);
      expect(find.text(_en.uiFileDropTooLarge('huge.jpg', 20)), findsOneWidget);
      expect(api.to('POST /files/presign'), isEmpty);
    });

    testWidgets('a failed upload can be sent again', (tester) async {
      var calls = 0;
      final api = _api(
        presign: (_) => calls++ == 0 ? apiError(500) : ok(_presigned('f1')),
      );
      final picking = await pump(tester, api);
      picking.photos = [
        LocalFile.bytes('page.jpg', [1]),
      ];
      await choose(tester, _en.appAttachTakePhoto);
      expect(find.text(_en.appAttachFailed), findsOneWidget);
      expect(changes.last, isEmpty);
      await tester.tap(find.byTooltip(_en.appAttachRetry));
      await tester.pumpAndSettle();
      expect(find.text(_en.appAttachFailed), findsNothing);
      expect(changes.last.single.id, 'f1');
    });

    testWidgets('photos only: no file chooser; the limit is kept', (
      tester,
    ) async {
      final picking = await pump(
        tester,
        _api(),
        purpose: FilePurpose.exam,
        maxFiles: 1,
      );
      await tester.tap(find.byKey(const Key('attach')));
      await tester.pumpAndSettle();
      expect(find.text(_en.appAttachChooseFile), findsNothing);
      picking.photos = [
        LocalFile.bytes('a.jpg', [1]),
        LocalFile.bytes('b.jpg', [2]),
      ];
      await tester.tap(find.text(_en.appAttachChoosePhotos));
      await tester.pumpAndSettle();
      expect(find.text(_en.appAttachTooMany(1)), findsOneWidget);
      expect(changes.last, hasLength(1));
    });

    testWidgets('almost full storage is said once', (tester) async {
      final picking = await pump(
        tester,
        _api(presign: (_) => ok(_presigned('f1', warning: true))),
      );
      picking.photos = [
        LocalFile.bytes('page.jpg', [1]),
      ];
      await choose(tester, _en.appAttachChoosePhotos);
      expect(find.text(_en.appAttachStorageAlmostFull), findsOneWidget);
    });
  });
}

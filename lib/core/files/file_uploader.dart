import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/config/app_config.dart';
import 'package:instructor_app/core/files/local_file.dart';

/// At most 20 MB per file (backend `MAX_UPLOAD_BYTES`).
const maxUploadBytes = 20 * 1024 * 1024;

const _images = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
const _documents = [
  'application/pdf',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'text/plain',
];

/// What a file is for (`purpose` in `POST /files/presign`), with the types
/// the server takes for it (backend `UPLOAD_RULES`).
enum FilePurpose {
  image('IMAGE', _images),
  exam('EXAM', _images),
  discussion('DISCUSSION', [..._images, ..._documents]),
  leave('LEAVE', [..._images, 'application/pdf']),
  // The server refuses HOMEWORK today (tes-taker#349); the types follow the
  // web's hand-in until the server says otherwise.
  homework('HOMEWORK', [..._images, ..._documents]);

  const FilePurpose(this.apiValue, this.mimes);

  final String apiValue;
  final List<String> mimes;

  bool allows(String mime) => mimes.contains(mime);
  bool get allowsDocuments => mimes.any((m) => !m.startsWith('image/'));
}

/// A file the server has (after `POST /files/:id/complete`).
@immutable
class UploadedFile {
  const UploadedFile({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
    this.storageWarning = false,
  });

  final String id;
  final String name;
  final String mime;
  final int size;

  /// The workspace has used 90% or more of its storage.
  final bool storageWarning;

  bool get isImage => mime.startsWith('image/');
}

/// Where a file can be seen: `GET /files/:id/content` redirects to a link
/// valid for an hour. It needs no sign-in (the id is unguessable), so it
/// works in an image and in the browser. Never keep the redirect target.
Uri fileContentUri(String fileId) =>
    Uri.parse('${AppConfig.apiBaseUrl}/files/$fileId/content');

/// Uploads in three steps (API guide §6): presign, PUT the bytes, complete.
/// Failures are [ApiException]s; over the storage quota the presign answers
/// 403 PLAN_LIMIT_REACHED, which the caller shows as the locked-feature sheet.
class FileUploader {
  FileUploader(this._api);

  final ApiClient _api;

  Future<UploadedFile> upload(
    FilePurpose purpose,
    LocalFile file, {
    String? scopeId,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final presigned = await _api.post(
      '/files/presign',
      data: {
        'purpose': purpose.apiValue,
        'mime': file.mime,
        'size': file.size,
        'name': file.name,
        'scope_id': ?scopeId,
      },
    );
    final p = presigned.object;
    final created = p['file'] as Map<String, dynamic>;
    final upload = p['upload'] as Map<String, dynamic>;
    final storage = p['storage'];
    await _api.putFile(
      Uri.parse(upload['url'] as String),
      data: file.open(),
      length: file.size,
      headers: {
        for (final MapEntry(:key, :value)
            in ((upload['headers'] as Map?) ?? const {}).entries)
          '$key': '$value',
      },
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
    final id = created['id'] as String;
    final done = (await _api.post('/files/$id/complete')).object;
    return UploadedFile(
      id: id,
      name: (done['name'] as String?) ?? file.name,
      mime: (done['mime'] as String?) ?? file.mime,
      size: (done['size_bytes'] as num?)?.toInt() ?? file.size,
      storageWarning: storage is Map && storage['warning'] == true,
    );
  }
}

final fileUploaderProvider = Provider<FileUploader>(
  (ref) => FileUploader(ref.watch(apiClientProvider)),
);

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:instructor_app/core/files/local_file.dart';

/// Photos come out at most this wide and as JPEG quality 80: small enough
/// for a phone network, sharp enough to read a page of homework. The server
/// compresses again (FND-15), as the web does after its own compression.
const _maxPhotoWidth = 2000.0;
const _photoQuality = 80;

/// Takes or chooses files. A provider so tests can hand in files without the
/// phone's pickers. Each returns nothing when the person cancels.
abstract class FilePicking {
  Future<LocalFile?> takePhoto();
  Future<List<LocalFile>> choosePhotos({int? limit});
  Future<List<LocalFile>> chooseFiles(List<String> extensions);
}

class DeviceFilePicking implements FilePicking {
  final _images = ImagePicker();

  Future<LocalFile> _fromXFile(XFile x) async {
    final name = x.name;
    final mime = mimeForName(name);
    return LocalFile(
      name: name,
      size: await x.length(),
      mime: mime.isNotEmpty ? mime : (x.mimeType ?? ''),
      open: x.openRead,
    );
  }

  @override
  Future<LocalFile?> takePhoto() async {
    final x = await _images.pickImage(
      source: ImageSource.camera,
      maxWidth: _maxPhotoWidth,
      imageQuality: _photoQuality,
    );
    return x == null ? null : _fromXFile(x);
  }

  @override
  Future<List<LocalFile>> choosePhotos({int? limit}) async {
    final picked = await _images.pickMultiImage(
      maxWidth: _maxPhotoWidth,
      imageQuality: _photoQuality,
      limit: limit != null && limit > 1 ? limit : null,
    );
    return [for (final x in picked) await _fromXFile(x)];
  }

  @override
  Future<List<LocalFile>> chooseFiles(List<String> extensions) async {
    final picked = await fp.FilePicker.pickFiles(
      type: fp.FileType.custom,
      allowedExtensions: extensions,
    );
    return [
      for (final f in picked)
        LocalFile(
          name: f.name,
          size: await f.length() ?? 0,
          mime: mimeForName(f.name),
          open: f.readAsByteStream,
        ),
    ];
  }
}

final filePickingProvider = Provider<FilePicking>((ref) => DeviceFilePicking());

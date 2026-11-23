import 'dart:io';

import 'package:flutter/foundation.dart';

/// A file on the phone, ready to upload: from the camera, the gallery or the
/// file chooser.
@immutable
class LocalFile {
  const LocalFile({
    required this.name,
    required this.size,
    required this.mime,
    required this.open,
  });

  /// A file at [path] (what the pickers give on Android and iOS).
  factory LocalFile.fromPath(String path, {String? name, int? size}) {
    final file = File(path);
    final fileName = name ?? path.split(Platform.pathSeparator).last;
    return LocalFile(
      name: fileName,
      size: size ?? file.lengthSync(),
      mime: mimeForName(fileName),
      open: file.openRead,
    );
  }

  /// In memory (tests).
  factory LocalFile.bytes(String name, List<int> bytes, {String? mime}) =>
      LocalFile(
        name: name,
        size: bytes.length,
        mime: mime ?? mimeForName(name),
        open: () => Stream.value(bytes),
      );

  final String name;
  final int size;

  /// From the file name's extension; empty when it is not one we know.
  final String mime;

  /// A fresh stream of the bytes each time (an upload can be retried).
  final Stream<List<int>> Function() open;
}

/// The types the server knows (backend `file-rules.ts`), by extension.
const _mimes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'txt': 'text/plain',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/x-m4a',
  'ogg': 'audio/ogg',
  'wav': 'audio/wav',
};

String mimeForName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return '';
  return _mimes[name.substring(dot + 1).toLowerCase()] ?? '';
}

/// Extensions for [mimes], for the file chooser's filter.
List<String> extensionsFor(Iterable<String> mimes) => [
  for (final MapEntry(:key, :value) in _mimes.entries)
    if (mimes.contains(value)) key,
];

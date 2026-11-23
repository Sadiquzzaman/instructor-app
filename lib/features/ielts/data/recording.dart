import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

/// Records the microphone to a file (IELTS Speaking).
abstract class SpeakingRecorder {
  /// Asks for the microphone when needed; false when refused.
  Future<bool> hasPermission();

  /// Starts recording to a new file.
  Future<void> start();

  /// Stops and gives the file's path (null when nothing was recorded).
  Future<String?> stop();

  Future<void> dispose();
}

class _RecordRecorder implements SpeakingRecorder {
  final _rec = AudioRecorder();

  @override
  Future<bool> hasPermission() => _rec.hasPermission();

  @override
  Future<void> start() => _rec.start(
    const RecordConfig(),
    path:
        '${Directory.systemTemp.path}/ielts-speaking-'
        '${DateTime.now().millisecondsSinceEpoch}.m4a',
  );

  @override
  Future<String?> stop() => _rec.stop();

  @override
  Future<void> dispose() => _rec.dispose();
}

/// Makes a recorder (a provider so tests can fake it).
final speakingRecorderProvider = Provider<SpeakingRecorder Function()>(
  (ref) => _RecordRecorder.new,
);

/// Plays a kept recording, with stop (a provider so tests can fake it).
abstract class RecordingPlayer {
  /// Plays [uri] to the end, or until [stop].
  Future<void> play(Uri uri);

  Future<void> stop();

  Future<void> dispose();
}

class _JustAudioRecordingPlayer implements RecordingPlayer {
  final _player = AudioPlayer();

  @override
  Future<void> play(Uri uri) async {
    await _player.setUrl(uri.toString());
    final done = _player.processingStateStream.firstWhere(
      (s) => s == ProcessingState.completed || s == ProcessingState.idle,
    );
    unawaited(_player.play());
    await done;
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

final recordingPlayerProvider = Provider<RecordingPlayer Function()>(
  (ref) => _JustAudioRecordingPlayer.new,
);

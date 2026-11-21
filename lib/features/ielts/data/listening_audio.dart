import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// Plays one recording from start to end: no pause, rewind or seeking,
/// only the volume (the real Listening test, IEL-04).
abstract class OncePlayer {
  /// Starts playing [uri]; completes when the recording has ended.
  Future<void> play(Uri uri);

  /// How far it has played, 0 to 1.
  Stream<double> get progress;

  Future<void> setVolume(double volume);

  Future<void> dispose();
}

class _JustAudioOncePlayer implements OncePlayer {
  final _player = AudioPlayer();

  @override
  Future<void> play(Uri uri) async {
    await _player.setUrl(uri.toString());
    final done = _player.processingStateStream.firstWhere(
      (s) => s == ProcessingState.completed,
    );
    unawaited(_player.play());
    await done;
  }

  @override
  Stream<double> get progress => _player.positionStream.map((p) {
    final total = _player.duration;
    if (total == null || total.inMilliseconds == 0) return 0;
    return (p.inMilliseconds / total.inMilliseconds).clamp(0, 1).toDouble();
  });

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() => _player.dispose();
}

/// Makes a player for one Listening part (a provider so tests can fake it).
final oncePlayerProvider = Provider<OncePlayer Function()>(
  (ref) => _JustAudioOncePlayer.new,
);

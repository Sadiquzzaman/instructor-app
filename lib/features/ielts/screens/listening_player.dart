import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/files/file_uploader.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/language_controller.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/features/ielts/data/attempts.dart';
import 'package:instructor_app/features/ielts/data/listening_audio.dart';

/// Where a part's played state is kept on the device, per attempt.
String listeningKey(String attemptId, String partId) =>
    'ielts.played.$attemptId.$partId';

/// A Listening part's recording, as in the real test (IEL-04): played
/// once, with no pause, rewind or seeking; only the volume changes. A
/// recording that was playing when the app was left counts as played.
class ListeningPlayer extends ConsumerStatefulWidget {
  const ListeningPlayer({
    required this.attemptId,
    required this.part,
    super.key,
  });

  final String attemptId;
  final PaperPart part;

  @override
  ConsumerState<ListeningPlayer> createState() => _ListeningPlayerState();
}

class _ListeningPlayerState extends ConsumerState<ListeningPlayer> {
  OncePlayer? _player;
  StreamSubscription<double>? _sub;
  double _progress = 0;
  double _volume = 1;

  /// ready, playing or done.
  late String _state = _stored();

  String get _key => listeningKey(widget.attemptId, widget.part.id);

  String _stored() {
    final s = ref.read(sharedPreferencesProvider).getString(_key);
    return s == 'playing' || s == 'done' ? 'done' : 'ready';
  }

  @override
  void dispose() {
    _sub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    final id = widget.part.audioFileId;
    if (id == null || _state != 'ready') return;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_key, 'playing');
    setState(() => _state = 'playing');
    final player = ref.read(oncePlayerProvider)();
    _player = player;
    _sub = player.progress.listen((p) {
      if (mounted) setState(() => _progress = p);
    });
    await player.setVolume(_volume);
    try {
      await player.play(fileContentUri(id));
      await prefs.setString(_key, 'done');
      if (mounted) setState(() => _state = 'done');
    } catch (_) {
      // Could not start (no connection): let the student try again.
      await prefs.setString(_key, 'ready');
      if (mounted) setState(() => _state = 'ready');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    if (widget.part.audioFileId == null) {
      return Text(
        l10n.ieltsTakeNoRecording,
        style: text.bodySmall?.copyWith(color: colors.inkMuted),
      );
    }
    return Container(
      key: Key('listening-${widget.part.id}'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.canvas,
        border: Border.all(color: colors.border),
        borderRadius: AppRadius.cardAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (_state == 'ready')
                FilledButton.icon(
                  key: Key('listening-play-${widget.part.id}'),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.ieltsTakePlayPart(widget.part.partNo)),
                  onPressed: _play,
                )
              else
                Text(
                  _state == 'playing'
                      ? l10n.ieltsTakePlaying
                      : l10n.ieltsTakePlayed,
                  key: Key('listening-state-${widget.part.id}'),
                  style: text.titleSmall,
                ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Semantics(
                  label: l10n.ieltsTakeRecordingProgress,
                  child: LinearProgressIndicator(
                    value: _state == 'done' ? 1 : _progress,
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.volume_up_outlined),
              Expanded(
                child: Slider(
                  key: Key('listening-volume-${widget.part.id}'),
                  value: _volume,
                  divisions: 10,
                  label: l10n.ieltsTakeVolume,
                  semanticFormatterCallback: (_) => l10n.ieltsTakeVolume,
                  onChanged: (v) {
                    setState(() => _volume = v);
                    unawaited(_player?.setVolume(v));
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

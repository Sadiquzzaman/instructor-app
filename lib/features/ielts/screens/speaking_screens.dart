import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/files/file_uploader.dart';
import 'package:instructor_app/core/files/local_file.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/text/html_text.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/ielts/data/ielts.dart';
import 'package:instructor_app/features/ielts/data/marking.dart';
import 'package:instructor_app/features/ielts/data/profiles.dart';
import 'package:instructor_app/features/ielts/data/recording.dart';
import 'package:instructor_app/features/ielts/screens/ielts_overview_screen.dart';
import 'package:instructor_app/features/ielts/screens/ielts_take_screens.dart';

/// Part 2: one minute to prepare, then up to two minutes to talk (IEL-07).
const prepareSeconds = 60;
const talkSeconds = 120;

String _hint(AppLocalizations l10n, int partNo) => switch (partNo) {
  1 => l10n.ieltsSpeakingPartHint1,
  2 => l10n.ieltsSpeakingPartHint2,
  _ => l10n.ieltsSpeakingPartHint3,
};

/// Plays a kept recording, with stop.
class RecordingButton extends ConsumerStatefulWidget {
  const RecordingButton({required this.fileId, required this.label, super.key});

  final String fileId;
  final String label;

  @override
  ConsumerState<RecordingButton> createState() => _RecordingButtonState();
}

class _RecordingButtonState extends ConsumerState<RecordingButton> {
  RecordingPlayer? _player;
  bool _playing = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player?.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    final p = _player ??= ref.read(recordingPlayerProvider)();
    setState(() => _playing = true);
    try {
      await p.play(fileContentUri(widget.fileId));
    } catch (_) {
      // Could not play now; the button is there to try again.
    }
    if (mounted) setState(() => _playing = false);
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: Key('recording-${widget.fileId}'),
    icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
    label: Text(widget.label),
    onPressed: _toggle,
  );
}

/// One Speaking part (IEL-07): the questions or cue card; Part 2's
/// preparation and talk timers; recording, kept with [onRecorded], and
/// recording again until it is handed in.
class SpeakingPartCard extends ConsumerStatefulWidget {
  const SpeakingPartCard({
    required this.partId,
    required this.partNo,
    required this.title,
    required this.content,
    required this.recordingId,
    required this.onRecorded,
    this.readOnly = false,
    super.key,
  });

  final String partId;
  final int partNo;
  final String? title;
  final String? content;
  final String? recordingId;
  final bool readOnly;
  final Future<void> Function(String fileId) onRecorded;

  @override
  ConsumerState<SpeakingPartCard> createState() => _SpeakingPartCardState();
}

class _SpeakingPartCardState extends ConsumerState<SpeakingPartCard> {
  SpeakingRecorder? _recorder;
  Timer? _timer;
  int? _prepare;
  int? _talk;

  /// idle, recording, uploading or denied.
  String _state = 'idle';

  @override
  void dispose() {
    _timer?.cancel();
    _recorder?.dispose();
    super.dispose();
  }

  void _count({bool talk = false}) {
    _timer?.cancel();
    setState(() {
      if (talk) {
        _talk = talkSeconds;
      } else {
        _prepare = prepareSeconds;
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        if (talk) {
          _talk = (_talk ?? 0) - 1;
        } else {
          _prepare = (_prepare ?? 0) - 1;
        }
      });
      if ((talk ? _talk : _prepare)! <= 0) t.cancel();
    });
  }

  Future<void> _start() async {
    final r = _recorder ??= ref.read(speakingRecorderProvider)();
    if (!await r.hasPermission()) {
      setState(() => _state = 'denied');
      return;
    }
    await r.start();
    setState(() => _state = 'recording');
  }

  Future<void> _stop() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final path = await _recorder?.stop();
    if (path == null) {
      setState(() => _state = 'idle');
      return;
    }
    setState(() => _state = 'uploading');
    try {
      final up = await ref
          .read(fileUploaderProvider)
          .upload(FilePurpose.ielts, LocalFile.fromPath(path));
      await widget.onRecorded(up.id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _state = 'idle');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    Widget clock(String label, int left) => Text(
      '$label ${OrgTime.clock(left < 0 ? 0 : left, lang)}',
      style: text.titleSmall?.copyWith(
        color: left <= 0 ? colors.danger : colors.ink,
      ),
    );
    return AppCard(
      key: Key('speaking-part-${widget.partId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.ieltsSpeakingPartN(widget.partNo), style: text.titleMedium),
          Text(_hint(l10n, widget.partNo), style: muted),
          if (widget.title?.isNotEmpty ?? false)
            Text(widget.title!, style: text.titleSmall),
          if (widget.content?.isNotEmpty ?? false)
            Text(htmlToText(widget.content!), style: text.bodyMedium),
          if (widget.partNo == 2 && !widget.readOnly) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton(
                  key: Key('speaking-prepare-${widget.partId}'),
                  onPressed: _count,
                  child: Text(l10n.ieltsSpeakingStartPreparation),
                ),
                OutlinedButton(
                  key: Key('speaking-talk-${widget.partId}'),
                  onPressed: () => _count(talk: true),
                  child: Text(l10n.ieltsSpeakingStartTalking),
                ),
                if (_prepare != null)
                  clock(l10n.ieltsSpeakingPrepare, _prepare!),
                if (_talk != null) clock(l10n.ieltsSpeakingTalk, _talk!),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.recordingId != null)
                RecordingButton(
                  fileId: widget.recordingId!,
                  label: l10n.ieltsSpeakingRecordingOf(widget.partNo),
                )
              else
                Text(l10n.ieltsSpeakingNoRecording, style: muted),
              if (!widget.readOnly)
                if (_state == 'recording')
                  FilledButton.icon(
                    key: Key('speaking-stop-${widget.partId}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.danger,
                    ),
                    icon: const Icon(Icons.stop),
                    label: Text(l10n.ieltsSpeakingStopRecording),
                    onPressed: _stop,
                  )
                else
                  OutlinedButton.icon(
                    key: Key('speaking-record-${widget.partId}'),
                    icon: const Icon(Icons.mic_none),
                    label: Text(
                      widget.recordingId == null
                          ? l10n.ieltsSpeakingRecord
                          : l10n.ieltsSpeakingRecordAgain,
                    ),
                    onPressed: _state == 'uploading' ? null : _start,
                  ),
              if (_state == 'uploading')
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (_state == 'denied')
                Text(
                  l10n.ieltsSpeakingMicrophoneDenied,
                  key: Key('speaking-denied-${widget.partId}'),
                  style: text.bodySmall?.copyWith(color: colors.warning),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The web's /ielts/speaking/[attemptId] (P10-06): the examiner's screen.
/// Parts 1–3 with Part 2's timers and recording for a live session (a
/// student's practice shows their recordings), and bands for the four
/// criteria with notes. Saving the marks ends a live session.
class IeltsExaminerScreen extends ConsumerStatefulWidget {
  const IeltsExaminerScreen({required this.attemptId, super.key});

  final String attemptId;

  @override
  ConsumerState<IeltsExaminerScreen> createState() =>
      _IeltsExaminerScreenState();
}

class _IeltsExaminerScreenState extends ConsumerState<IeltsExaminerScreen> {
  Map<String, num?>? _given;
  TextEditingController? _notes;
  bool _busy = false;

  @override
  void dispose() {
    _notes?.dispose();
    super.dispose();
  }

  Future<void> _save(Map<String, num?> c) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(apiClientProvider)
          .put(
            '/ielts/marking/${widget.attemptId}/speaking',
            data: {
              'criteria': {for (final k in speakingCriteria) k: c[k]},
              if (_notes!.text.trim().isNotEmpty)
                'feedback': _notes!.text.trim(),
            },
          );
      messenger.showSnackBar(SnackBar(content: Text(l10n.ieltsSpeakingSaved)));
      ref.invalidate(ieltsMarkingProvider(widget.attemptId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    return ref
        .watch(ieltsMarkingProvider(widget.attemptId))
        .when(
          loading: () => LoadingView(semanticsLabel: l10n.ieltsSpeakingMarks),
          error: (e, _) => ErrorView(
            title: e is ApiException && e.statusCode == 409
                ? l10n.ieltsSpeakingNotHandedIn
                : l10n.ieltsSpeakingLoadFailed,
            retryLabel: l10n.uiErrorRetry,
            onRetry: () =>
                ref.invalidate(ieltsMarkingProvider(widget.attemptId)),
          ),
          data: (v) {
            if (v == null) {
              return EmptyView(
                icon: Icons.record_voice_over_outlined,
                title: l10n.ieltsSpeakingLoadFailed,
              );
            }
            final live = v.mode == 'LIVE';
            final c = _given ?? {...?v.speaking};
            _notes ??= TextEditingController(text: v.feedback ?? '');
            final preview = criteriaBand(c, speakingCriteria);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Text(
                      l10n.ieltsSpeakingExaminerTitle(v.studentName),
                      style: text.headlineSmall,
                    ),
                    Text(
                      '${v.testTitle} · ${v.batch} · '
                      '${live ? l10n.ieltsSpeakingLive : l10n.ieltsSpeakingPractice}',
                      style: muted,
                    ),
                    if (v.band != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      IeltsStat(
                        l10n.ieltsSpeakingSpeakingBand,
                        bandText(v.band, lang),
                      ),
                    ],
                    for (final t in v.tasks)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: SpeakingPartCard(
                          key: ValueKey('${t.partId}-${t.recordingFileId}'),
                          partId: t.partId,
                          partNo: t.partNo,
                          title: t.title,
                          content: t.content,
                          recordingId: t.recordingFileId,
                          readOnly: !live || v.status == 'MARKED',
                          onRecorded: (fileId) async {
                            await ref
                                .read(apiClientProvider)
                                .put(
                                  '/ielts/marking/${widget.attemptId}/recordings',
                                  data: {
                                    'part_id': t.partId,
                                    'file_id': fileId,
                                  },
                                );
                            ref.invalidate(
                              ieltsMarkingProvider(widget.attemptId),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(l10n.ieltsSpeakingMarks, style: text.titleSmall),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              for (final k in speakingCriteria)
                                SizedBox(
                                  width: 200,
                                  child: DropdownButtonFormField<num>(
                                    key: Key('criterion-$k'),
                                    initialValue: ieltsBands.contains(c[k])
                                        ? c[k]
                                        : null,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: criterionName(l10n, k),
                                    ),
                                    items: [
                                      for (final b in ieltsBands)
                                        DropdownMenuItem(
                                          value: b,
                                          child: Text(bandText(b, lang)),
                                        ),
                                    ],
                                    onChanged: (b) =>
                                        setState(() => _given = {...c, k: b}),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            preview == null
                                ? l10n.ieltsSpeakingBandPending
                                : l10n.ieltsSpeakingBandPreview(
                                    bandText(preview, lang),
                                  ),
                            key: const Key('speaking-preview'),
                            style: text.titleSmall,
                          ),
                          TextField(
                            key: const Key('speaking-notes'),
                            controller: _notes,
                            minLines: 3,
                            maxLines: 8,
                            decoration: InputDecoration(
                              labelText: l10n.ieltsSpeakingNotes,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: FilledButton(
                              key: const Key('speaking-save'),
                              onPressed: _busy || preview == null
                                  ? null
                                  : () => _save(c),
                              child: Text(
                                live && v.status != 'MARKED'
                                    ? l10n.ieltsSpeakingSaveAndEnd
                                    : l10n.ieltsSpeakingSaveMarks,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
  }
}

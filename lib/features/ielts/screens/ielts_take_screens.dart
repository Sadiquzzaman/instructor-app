import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/files/open_file.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/text/html_text.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/time/clock.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/ielts/data/attempts.dart';
import 'package:instructor_app/features/ielts/data/builder.dart';
import 'package:instructor_app/features/ielts/data/ielts.dart';
import 'package:instructor_app/features/ielts/screens/ielts_overview_screen.dart';
import 'package:instructor_app/features/ielts/screens/ielts_tests_screens.dart';
import 'package:instructor_app/features/ielts/screens/listening_player.dart';
import 'package:instructor_app/features/ielts/screens/speaking_screens.dart';

/// Modules the app takes on screen (Speaking as practice recordings; a
/// live session is run by the teacher).
const ieltsOnScreen = {'LISTENING', 'READING', 'WRITING', 'SPEAKING'};

/// Mocks need a computer or a tablet (the owner's decision, 15 Nov 2026).
const ieltsMinMockWidth = 768.0;

String ieltsAttemptRoute(String id) => '/ielts/attempts/$id';

String criterionName(AppLocalizations l10n, String key) => switch (key) {
  'TA' => l10n.ieltsTakeCriteriaTA,
  'TR' => l10n.ieltsTakeCriteriaTR,
  'CC' => l10n.ieltsTakeCriteriaCC,
  'LR' => l10n.ieltsTakeCriteriaLR,
  'GRA' => l10n.ieltsTakeCriteriaGRA,
  'FC' => l10n.ieltsTakeCriteriaFC,
  _ => l10n.ieltsTakeCriteriaP,
};

/// Criteria in the official order.
List<MapEntry<String, num>> orderedCriteria(Map<dynamic, dynamic> c) => [
  for (final k in ieltsCriteriaOrder)
    if (c[k] is num) MapEntry(k, c[k] as num),
];

/// The web's /ielts/my (P10-04): what is opened for the student's batches,
/// with each module's state — start (after a reminder of the time),
/// continue, or the band.
class MyIeltsTestsScreen extends ConsumerStatefulWidget {
  const MyIeltsTestsScreen({super.key});

  @override
  ConsumerState<MyIeltsTestsScreen> createState() => _MyIeltsTestsScreenState();
}

class _MyIeltsTestsScreenState extends ConsumerState<MyIeltsTestsScreen> {
  bool _busy = false;

  Future<void> _start(IeltsMyOpening o, String module) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final minutes =
        (((o.durations[module] ?? 0) + (module == 'LISTENING' ? 120 : 0)) / 60)
            .round();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.ieltsTakeStartTitle(ieltsModuleShort(l10n, module))),
        content: Text(
          module == 'LISTENING'
              ? l10n.ieltsTakeStartListening(minutes)
              : module == 'SPEAKING'
              ? l10n.ieltsTakeStartSpeaking
              : l10n.ieltsTakeStartOther(minutes),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.ieltsTakeNotYet),
          ),
          FilledButton(
            key: const Key('ielts-start-confirm'),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.ieltsTakeStart),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final r = await ref
          .read(apiClientProvider)
          .post('/ielts/my/assignments/${o.id}/modules/$module/start');
      final id = attemptFromJson(r.payload)?.id;
      if (id != null) unawaited(router.push(ieltsAttemptRoute(id)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      ref.invalidate(myIeltsOpeningsProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _action(IeltsMyOpening o, String module) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    final a = o.attempts[module];
    Widget note(String s) => Text(s, style: muted);
    if (a != null && a.status == 'IN_PROGRESS' && a.mode == 'LIVE') {
      return note(l10n.ieltsTakeWithTeacher);
    }
    if (a != null && a.status == 'IN_PROGRESS') {
      return FilledButton(
        key: Key('ielts-continue-${o.id}-$module'),
        onPressed: () => context.push(ieltsAttemptRoute(a.id)),
        child: Text(l10n.ieltsTakeContinue),
      );
    }
    if (a != null) {
      return Wrap(
        spacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            a.band == null
                ? l10n.ieltsTakeWaitingForMarks
                : l10n.ieltsTakeBandShort(bandText(a.band, lang)),
            style: text.bodySmall,
          ),
          TextButton(
            key: Key('ielts-result-${o.id}-$module'),
            onPressed: () => context.push(ieltsAttemptRoute(a.id)),
            child: Text(l10n.ieltsTakeViewResult),
          ),
        ],
      );
    }
    if (module == 'SPEAKING' && o.purpose == 'MOCK') {
      return note(l10n.ieltsTakeWithTeacher);
    }
    if (!ieltsOnScreen.contains(module)) {
      return note(l10n.ieltsTakeNotOnScreenYet);
    }
    if (!o.isOpen) return note(l10n.ieltsTakeNotOpen);
    if (waitsForEarlier(o, module)) return note(l10n.ieltsTakeAfterPrevious);
    return FilledButton(
      key: Key('ielts-start-${o.id}-$module'),
      onPressed: _busy ? null : () => _start(o, module),
      child: Text(l10n.ieltsTakeStart),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ref
            .watch(myIeltsOpeningsProvider)
            .when(
              loading: () => LoadingView(semanticsLabel: l10n.ieltsTakeMyTitle),
              error: (e, _) => ErrorView(
                title: e is ApiException && e.statusCode == 403
                    ? l10n.ieltsTestsNotAvailable
                    : l10n.ieltsTakeLoadFailed,
                retryLabel: l10n.uiErrorRetry,
                onRetry: () => ref.invalidate(myIeltsOpeningsProvider),
              ),
              data: (rows) => RefreshIndicator(
                onRefresh: () => ref.refresh(myIeltsOpeningsProvider.future),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Text(l10n.ieltsTakeMyTitle, style: text.headlineSmall),
                    Text(l10n.ieltsTakeMyDescription, style: muted),
                    const SizedBox(height: AppSpacing.md),
                    if (rows.isEmpty)
                      EmptyView(
                        icon: Icons.quiz_outlined,
                        title: l10n.ieltsTakeNoneOpen,
                        message: l10n.ieltsTakeNoneOpenHint,
                      )
                    else
                      for (final o in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: AppCard(
                            key: Key('my-ielts-${o.id}'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        o.testTitle,
                                        style: text.titleMedium,
                                      ),
                                    ),
                                    Chip(
                                      label: Text(
                                        ieltsPurpose(l10n, o.purpose),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                                Text(
                                  l10n.ieltsTakeWindow(
                                    o.opens == null
                                        ? '—'
                                        : OrgTime.dateTime(o.opens!, lang),
                                    o.closes == null
                                        ? '—'
                                        : OrgTime.dateTime(o.closes!, lang),
                                  ),
                                  style: muted,
                                ),
                                for (final m in o.modules)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: AppSpacing.sm,
                                    ),
                                    child: Wrap(
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: AppSpacing.sm,
                                      runSpacing: AppSpacing.xs,
                                      children: [
                                        Text(
                                          '${ieltsModuleShort(l10n, m)} · '
                                          '${l10n.ieltsTakeMinutes(((o.durations[m] ?? 0) / 60).round())}',
                                          style: text.bodyMedium,
                                        ),
                                        _action(o, m),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}

/// The web's /ielts/attempts/[id] (P10-04, P10-05): a module in the
/// computer-delivered layout. The timer runs from the server's clock and
/// the module is handed in by itself at 0:00; answers save 1.5 seconds
/// after a change and again until the server has them. Reading shows the
/// passage beside its questions on a tablet (above them on a phone);
/// Writing shows the task beside the answer box with a live word count.
/// After hand-in: the score and band, or the Writing marks.
class IeltsAttemptScreen extends ConsumerStatefulWidget {
  const IeltsAttemptScreen({required this.id, super.key});

  final String id;

  @override
  ConsumerState<IeltsAttemptScreen> createState() => _IeltsAttemptScreenState();
}

class _IeltsAttemptScreenState extends ConsumerState<IeltsAttemptScreen> {
  IeltsAttemptView? _view;
  Object? _error;
  final _answers = <String, String>{};
  final _dirty = <String>{};
  final _flagged = <String>{};
  Timer? _save;
  Timer? _tick;
  Duration _offset = Duration.zero;
  int? _remaining;
  int _part = 0;
  bool _handingIn = false;

  /// idle, saving, saved or error.
  String _saveState = 'idle';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _save?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  void _take(IeltsAttemptView v) {
    final now = ref.read(clockProvider)();
    _offset = (v.now ?? now).difference(now);
    _answers
      ..clear()
      ..addAll(v.answers);
    _view = v;
    _tick?.cancel();
    if (v.status == 'IN_PROGRESS' && v.deadline != null) {
      _countDown();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _countDown());
    }
  }

  void _countDown() {
    final d = _view?.deadline;
    if (d == null) return;
    final left = d.difference(ref.read(clockProvider)().add(_offset)).inSeconds;
    setState(() => _remaining = left < 0 ? 0 : left);
    if (left <= 0) unawaited(_submit());
  }

  Future<void> _load() async {
    try {
      final r = await ref
          .read(apiClientProvider)
          .get('/ielts/my/attempts/${widget.id}');
      final v = attemptFromJson(r.payload);
      if (!mounted) return;
      setState(() {
        _error = null;
        if (v != null) _take(v);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _setAnswer(String id, String value) {
    setState(() {
      _answers[id] = value;
      _dirty.add(id);
    });
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 1500), _flush);
  }

  Future<void> _flush() async {
    _save?.cancel();
    final v = _view;
    if (v == null || _dirty.isEmpty || _handingIn) return;
    final ids = [..._dirty];
    _dirty.clear();
    setState(() => _saveState = 'saving');
    try {
      await ref
          .read(apiClientProvider)
          .put(
            '/ielts/my/attempts/${v.id}/answers',
            data: {
              'answers': [
                for (final id in ids)
                  answerEntry(
                    v.module,
                    id,
                    (_answers[id] ?? '').isEmpty ? null : _answers[id],
                  ),
              ],
            },
          );
      if (mounted) {
        setState(() => _saveState = _dirty.isEmpty ? 'saved' : 'saving');
      }
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        await _load();
        return;
      }
      _dirty.addAll(ids);
      if (mounted) setState(() => _saveState = 'error');
      // Offline or refused for now: try again shortly.
      _save = Timer(const Duration(seconds: 10), _flush);
    }
  }

  /// Hands in with every answer, so nothing waits on a pending save.
  Future<void> _submit() async {
    final v = _view;
    if (v == null || _handingIn) return;
    _handingIn = true;
    _save?.cancel();
    _tick?.cancel();
    setState(() {});
    try {
      final r = await ref
          .read(apiClientProvider)
          .post(
            '/ielts/my/attempts/${v.id}/submit',
            data: {
              'answers': [
                for (final e in _answers.entries)
                  answerEntry(
                    v.module,
                    e.key,
                    e.value.isEmpty ? null : e.value,
                  ),
              ],
            },
          );
      _dirty.clear();
      final next = attemptFromJson(r.payload);
      if (mounted && next != null) setState(() => _take(next));
      ref.invalidate(myIeltsOpeningsProvider);
    } catch (_) {
      _handingIn = false;
      await _load();
    } finally {
      _handingIn = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _confirmHandIn() async {
    final l10n = context.l10n;
    final v = _view!;
    final parts = v.parts ?? const [];
    final writing = v.module == 'WRITING';
    final speaking = v.module == 'SPEAKING';
    final missing = speaking
        ? parts.where((p) => v.recordings[p.id] == null).length
        : writing
        ? parts.where((p) => essayWords(_answers[p.id] ?? '') == 0).length
        : unansweredNumbers(parts, _answers);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.ieltsTakeHandInTitle),
        content: Text(
          missing == 0
              ? l10n.ieltsTakeHandInAll
              : speaking
              ? l10n.ieltsTakeHandInNoRecording(missing)
              : writing
              ? l10n.ieltsTakeHandInEmptyTasks(missing)
              : l10n.ieltsTakeHandInUnanswered(missing),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.ieltsTakeKeepWorking),
          ),
          FilledButton(
            key: const Key('ielts-handin-confirm'),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.ieltsTakeHandIn),
          ),
        ],
      ),
    );
    if (ok == true) await _submit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final v = _view;
    if (_error != null) {
      final e = _error;
      return ErrorView(
        title: e is ApiException && e.statusCode == 404
            ? l10n.ieltsTakeNotFound
            : l10n.ieltsTakeLoadFailed,
        retryLabel: l10n.uiErrorRetry,
        onRetry: _load,
      );
    }
    if (v == null) return LoadingView(semanticsLabel: l10n.ieltsTakeMyTitle);
    if (v.status != 'IN_PROGRESS') {
      return _ResultView(view: v, answers: _answers);
    }
    final width = MediaQuery.sizeOf(context).width;
    if (v.purpose == 'MOCK' && width < ieltsMinMockWidth) {
      return _Notice(text: l10n.ieltsTakeNeedComputer);
    }
    if (!ieltsOnScreen.contains(v.module)) {
      return _Notice(text: l10n.appNotYetIelts);
    }
    return _paper(context, v);
  }

  Widget _paper(BuildContext context, IeltsAttemptView v) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final parts = v.parts ?? const <PaperPart>[];
    if (parts.isEmpty) return _Notice(text: l10n.ieltsTakeLoadFailed);
    final part = parts[_part.clamp(0, parts.length - 1)];
    final wide =
        MediaQuery.sizeOf(context).width >= AppSpacing.tabletBreakpoint;
    final low = _remaining != null && _remaining! <= 5 * 60;
    final saveText = switch (_saveState) {
      'saving' => l10n.ieltsTakeSaving,
      'saved' => l10n.ieltsTakeSaved,
      'error' => l10n.ieltsTakeSaveFailed,
      _ => '',
    };
    final writing = v.module == 'WRITING';
    final listening = v.module == 'LISTENING';
    final speaking = v.module == 'SPEAKING';
    final groups = [
      for (final g in part.groups)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: PaperGroupView(
            group: g,
            answers: _answers,
            onAnswer: _setAnswer,
            readOnly: false,
            flagged: _flagged,
            onFlag: (id) => setState(
              () => _flagged.contains(id)
                  ? _flagged.remove(id)
                  : _flagged.add(id),
            ),
          ),
        ),
    ];
    Widget pane(List<Widget> children, Key key) => ListView(
      key: key,
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: children,
    );
    final source = <Widget>[
      if (listening) ...[
        Text(
          ieltsPartName(l10n, part.module, part.partNo),
          style: text.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        ListeningPlayer(
          key: ValueKey('player-${v.id}-${part.id}'),
          attemptId: v.id,
          part: part,
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      if (part.title?.isNotEmpty ?? false)
        Text(part.title!, style: text.titleMedium),
      if (part.content?.isNotEmpty ?? false)
        SelectableText(htmlToText(part.content!), style: text.bodyMedium),
      if (part.imageFileId != null)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            icon: const Icon(Icons.image_outlined),
            label: Text(l10n.ieltsTakePicture),
            onPressed: () => openFile(context, ref, part.imageFileId!),
          ),
        ),
    ];
    final speakingPane = <Widget>[
      Text(l10n.ieltsTakeSpeakingPracticeHint, style: text.bodySmall),
      for (final p in parts)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: SpeakingPartCard(
            key: ValueKey('${p.id}-${v.recordings[p.id]}'),
            partId: p.id,
            partNo: p.partNo,
            title: p.title,
            content: p.content,
            recordingId: v.recordings[p.id],
            onRecorded: (fileId) async {
              final r = await ref
                  .read(apiClientProvider)
                  .put(
                    '/ielts/my/attempts/${v.id}/recordings',
                    data: {'part_id': p.id, 'file_id': fileId},
                  );
              final next = attemptFromJson(r.payload);
              if (mounted && next != null) setState(() => _take(next));
            },
          ),
        ),
    ];
    final answerPane = writing
        ? <Widget>[
            _WritingBox(
              key: ValueKey('writing-${part.id}'),
              part: part,
              value: _answers[part.id] ?? '',
              onChanged: (s) => _setAnswer(part.id, s),
            ),
          ]
        : groups;
    return Column(
      children: [
        Material(
          color: colors.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v.testTitle,
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        ieltsModuleShort(l10n, v.module),
                        style: text.titleSmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  saveText,
                  key: const Key('ielts-save-state'),
                  style: text.bodySmall,
                ),
                const SizedBox(width: AppSpacing.sm),
                Semantics(
                  label: l10n.ieltsTakeTimeLeft,
                  child: Text(
                    _remaining == null
                        ? '--:--'
                        : OrgTime.clock(_remaining!, lang),
                    key: const Key('ielts-timer'),
                    style: text.titleMedium?.copyWith(
                      color: low ? colors.danger : colors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  key: const Key('ielts-handin'),
                  onPressed: _handingIn ? null : _confirmHandIn,
                  child: Text(l10n.ieltsTakeHandIn),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: speaking
              ? pane(speakingPane, Key('speaking-${v.id}'))
              : wide && !listening
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: pane(source, Key('source-${part.id}'))),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: pane(answerPane, Key('answers-${part.id}')),
                    ),
                  ],
                )
              : pane([
                  ...source,
                  const SizedBox(height: AppSpacing.md),
                  ...answerPane,
                ], Key('paper-${part.id}')),
        ),
        const Divider(height: 1),
        Material(
          color: colors.surface,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                for (final (i, p) in parts.indexed) ...[
                  TextButton(
                    key: Key('ielts-part-$i'),
                    style: i == _part
                        ? TextButton.styleFrom(
                            backgroundColor: colors.primary,
                            foregroundColor: colors.inkInverse,
                          )
                        : null,
                    onPressed: () => setState(() => _part = i),
                    child: Text(ieltsPartName(l10n, p.module, p.partNo)),
                  ),
                  for (final g in p.groups)
                    for (final q in g.questions)
                      for (var n = q.numberFrom; n <= q.numberTo; n++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: InkWell(
                            key: Key('ielts-nav-$n'),
                            onTap: () => setState(() => _part = i),
                            child: Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: AppRadius.inputAll,
                                border: Border.all(
                                  color: _flagged.contains(q.id)
                                      ? colors.warning
                                      : (_answers[q.id] ?? '').isNotEmpty
                                      ? colors.primary
                                      : colors.border,
                                ),
                                color: _flagged.contains(q.id)
                                    ? colors.warningSoft
                                    : (_answers[q.id] ?? '').isNotEmpty
                                    ? colors.primarySoft
                                    : null,
                              ),
                              child: Text(
                                OrgTime.number(n, lang),
                                style: text.labelSmall,
                                semanticsLabel: l10n.ieltsTakeGoTo(
                                  '$n',
                                  _flagged.contains(q.id)
                                      ? 'flagged'
                                      : (_answers[q.id] ?? '').isNotEmpty
                                      ? 'answered'
                                      : 'open',
                                ),
                              ),
                            ),
                          ),
                        ),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            key: const Key('ielts-notice'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: () => context.go('/ielts/my'),
            child: Text(context.l10n.ieltsTakeBackToTests),
          ),
        ],
      ),
    ),
  );
}

/// A Writing task's answer box with the live word count; fewer words than
/// asked is shown, not blocked.
class _WritingBox extends StatefulWidget {
  const _WritingBox({
    required this.part,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final PaperPart part;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_WritingBox> createState() => _WritingBoxState();
}

class _WritingBoxState extends State<_WritingBox> {
  late final _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final words = essayWords(_c.text);
    final min = ieltsMinWords[widget.part.partNo] ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.ieltsTakeYourAnswer, style: text.titleSmall),
        TextField(
          key: Key('writing-box-${widget.part.id}'),
          controller: _c,
          minLines: 12,
          maxLines: null,
          maxLength: 20000,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            hintText: l10n.ieltsTakeAnswerFor(widget.part.partNo),
            counterText: '',
          ),
          onChanged: (s) {
            setState(() {});
            widget.onChanged(s);
          },
        ),
        Text(
          words < min
              ? '${l10n.ieltsTakeWordCount(words)} · ${l10n.ieltsTakeUnderMinimum(min)}'
              : l10n.ieltsTakeWordCount(words),
          key: Key('writing-count-${widget.part.id}'),
          style: text.bodySmall?.copyWith(
            color: words < min ? colors.warning : colors.inkMuted,
          ),
        ),
      ],
    );
  }
}

/// One question group as on the paper: the instruction, a picture, the
/// list to choose from, the text with its gaps, and each question with its
/// control and a flag for review. Read-only after hand-in, with the right
/// answers when they may be shown.
class PaperGroupView extends ConsumerWidget {
  const PaperGroupView({
    required this.group,
    required this.answers,
    required this.onAnswer,
    required this.readOnly,
    required this.flagged,
    required this.onFlag,
    super.key,
  });

  final PaperGroup group;
  final Map<String, String> answers;
  final void Function(String id, String value) onAnswer;
  final bool readOnly;
  final Set<String> flagged;
  final ValueChanged<String> onFlag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final rule = ieltsGroupRules[group.type];
    final choicesKind = rule?.choices ?? IeltsChoices.text;
    final shared = group.shared;
    final writes = choicesKind == IeltsChoices.text && shared.isEmpty;
    String label(PaperQuestion q) => q.numberFrom == q.numberTo
        ? OrgTime.number(q.numberFrom, lang)
        : '${OrgTime.number(q.numberFrom, lang)}–${OrgTime.number(q.numberTo, lang)}';
    List<IeltsOption> choicesOf(PaperQuestion q) => switch (choicesKind) {
      IeltsChoices.question => q.options ?? const [],
      IeltsChoices.fixed => [
        for (final k in rule?.fixed ?? const <String>[]) (key: k, text: k),
      ],
      _ => shared,
    };

    Widget review(PaperQuestion q) {
      if (q.keys == null && q.accepted == null) return const SizedBox.shrink();
      final right = (q.marks ?? 0) > 0;
      final key = (q.keys?.isNotEmpty ?? false)
          ? q.keys!.join(', ')
          : (q.accepted ?? const []).join(' / ');
      return Text(
        right
            ? l10n.ieltsTakeRight
            : '${l10n.ieltsTakeWrong} · ${l10n.ieltsTakeRightAnswer(key)}',
        style: text.bodySmall?.copyWith(
          color: right ? colors.success : colors.danger,
        ),
      );
    }

    Widget control(PaperQuestion q) {
      final value = answers[q.id] ?? '';
      if (writes) {
        return TextFormField(
          key: Key('answer-${q.id}'),
          initialValue: value,
          enabled: !readOnly,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: l10n.ieltsTakeQuestionLabel(label(q)),
          ),
          onChanged: (s) => onAnswer(q.id, s),
        );
      }
      final choices = choicesOf(q);
      if (choicesKind == IeltsChoices.shared ||
          choicesKind == IeltsChoices.text) {
        return DropdownButtonFormField<String>(
          key: Key('answer-${q.id}'),
          initialValue: choices.any((c) => c.key == value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.ieltsTakeQuestionLabel(label(q)),
            hintText: l10n.ieltsTakeChoose,
          ),
          items: [
            for (final c in choices)
              DropdownMenuItem(value: c.key, child: Text(c.key)),
          ],
          onChanged: readOnly ? null : (v) => onAnswer(q.id, v ?? ''),
        );
      }
      if (group.type == 'MCQ_MULTI') {
        final chosen = value.isEmpty ? <String>[] : value.split(',');
        final max = q.numberTo - q.numberFrom + 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.ieltsTakeChooseN(max), style: text.bodySmall),
            for (final c in choices)
              CheckboxListTile(
                key: Key('answer-${q.id}-${c.key}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('${c.key}  ${c.text}'),
                value: chosen.contains(c.key),
                onChanged:
                    readOnly ||
                        (!chosen.contains(c.key) && chosen.length >= max)
                    ? null
                    : (_) {
                        final next = chosen.contains(c.key)
                            ? [
                                for (final k in chosen)
                                  if (k != c.key) k,
                              ]
                            : [...chosen, c.key];
                        next.sort();
                        onAnswer(q.id, next.join(','));
                      },
              ),
          ],
        );
      }
      return RadioGroup<String>(
        groupValue: value.isEmpty ? null : value,
        onChanged: (v) {
          if (!readOnly && v != null) onAnswer(q.id, v);
        },
        child: Column(
          children: [
            for (final c in choices)
              RadioListTile<String>(
                key: Key('answer-${q.id}-${c.key}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                enabled: !readOnly,
                value: c.key,
                title: Text(
                  choicesKind == IeltsChoices.question
                      ? '${c.key}  ${c.text}'
                      : c.text,
                ),
              ),
          ],
        ),
      );
    }

    Widget flag(PaperQuestion q) => readOnly
        ? const SizedBox.shrink()
        : TextButton(
            key: Key('flag-${q.id}'),
            onPressed: () => onFlag(q.id),
            child: Text(
              flagged.contains(q.id)
                  ? l10n.ieltsTakeFlagged
                  : l10n.ieltsTakeFlag,
              semanticsLabel: l10n.ieltsTakeFlagLabel(label(q)),
            ),
          );

    final from = group.numberFrom ?? 0;
    final to = group.numberTo ?? 0;
    return Column(
      key: Key('paper-group-${group.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          from == to
              ? l10n.ieltsTakeQuestionLabel(OrgTime.number(from, lang))
              : l10n.ieltsTakeGroupLabel(from, to),
          style: text.titleSmall,
        ),
        Text(group.instruction, style: text.bodyMedium),
        if (group.imageFileId != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.image_outlined),
              label: Text(l10n.ieltsTakePicture),
              onPressed: () => openFile(context, ref, group.imageFileId!),
            ),
          ),
        if (shared.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: colors.canvas,
              borderRadius: AppRadius.cardAll,
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final o in shared)
                  Text('${o.key}  ${o.text}', style: text.bodySmall),
              ],
            ),
          ),
        if (group.gapText?.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              group.gapText!.replaceAllMapped(RegExp(r'\[\[(\d+)\]\]'), (m) {
                final i = int.parse(m[1]!) - 1;
                if (i < 0 || i >= group.questions.length) return '____';
                return '(${OrgTime.number(group.questions[i].numberFrom, lang)}) ____';
              }),
              style: text.bodyMedium,
            ),
          ),
        for (final q in group.questions)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${label(q)}. ${q.prompt ?? ''}',
                        style: text.bodyMedium,
                      ),
                    ),
                    flag(q),
                  ],
                ),
                control(q),
                review(q),
              ],
            ),
          ),
      ],
    );
  }
}

/// After hand-in: the score out of 40 and band, or Writing's marks.
class _ResultView extends ConsumerWidget {
  const _ResultView({required this.view, required this.answers});

  final IeltsAttemptView view;
  final Map<String, String> answers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    final v = view;
    final parts = v.parts;
    final writing = v.module == 'WRITING';
    final speaking = v.module == 'SPEAKING';
    final tasks = [
      for (final t in (v.criteria?['tasks'] as List?) ?? const [])
        if (t is Map) t,
    ];
    final speakingCriteria = v.criteria?['speaking'] is Map
        ? v.criteria!['speaking']! as Map
        : null;
    Widget criteriaGrid(Map<dynamic, dynamic> c) => Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.xs,
      children: [
        for (final e in orderedCriteria(c))
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(criterionName(l10n, e.key), style: muted),
              Text(bandText(e.value, lang), style: text.titleSmall),
            ],
          ),
      ],
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(v.testTitle, style: muted),
            Text(
              l10n.ieltsTakeResultTitle(ieltsModuleShort(l10n, v.module)),
              style: text.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            if (writing || speaking) ...[
              if (v.band == null)
                Text(
                  speaking
                      ? l10n.ieltsTakeWaitingForTeacherSpeaking
                      : l10n.ieltsTakeWaitingForTeacher,
                  key: const Key('ielts-waiting'),
                )
              else
                IeltsStat(l10n.ieltsTakeBand, bandText(v.band, lang)),
              if (speakingCriteria != null) ...[
                const SizedBox(height: AppSpacing.sm),
                AppCard(child: criteriaGrid(speakingCriteria)),
              ],
              if (v.feedback?.isNotEmpty ?? false) ...[
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l10n.ieltsTakeFeedback, style: text.titleSmall),
                      Text(v.feedback!),
                    ],
                  ),
                ),
              ],
              if (speaking)
                for (final p in parts ?? const <PaperPart>[])
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: SpeakingPartCard(
                      partId: p.id,
                      partNo: p.partNo,
                      title: p.title,
                      content: p.content,
                      recordingId: v.recordings[p.id],
                      readOnly: true,
                      onRecorded: (_) async {},
                    ),
                  ),
              if (writing)
                for (final p in parts ?? const <PaperPart>[])
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            ieltsPartName(l10n, p.module, p.partNo),
                            style: text.titleSmall,
                          ),
                          for (final t in tasks)
                            if (t['part_id'] == p.id) ...[
                              Text(
                                l10n.ieltsTakeTaskBand(
                                  bandText(t['band'] as num?, lang),
                                ),
                                style: text.bodyMedium,
                              ),
                              if (t['criteria'] is Map)
                                criteriaGrid(t['criteria'] as Map),
                              if ((t['comment'] as String?)?.isNotEmpty ??
                                  false)
                                Text(t['comment'] as String),
                            ],
                          Text(
                            l10n.ieltsTakeWordCount(
                              essayWords(answers[p.id] ?? ''),
                            ),
                            style: muted,
                          ),
                          Text(
                            (answers[p.id] ?? '').isEmpty
                                ? '—'
                                : answers[p.id]!,
                          ),
                        ],
                      ),
                    ),
                  ),
            ] else ...[
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  IeltsStat(
                    l10n.ieltsTakeRawScore,
                    v.rawScore == null
                        ? '—'
                        : l10n.ieltsTakeScoreOutOf(
                            v.rawScore!,
                            v.rawTotal ?? 40,
                          ),
                  ),
                  IeltsStat(l10n.ieltsTakeBand, bandText(v.band, lang)),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (parts == null)
                Text(l10n.ieltsTakeAnswersLater, key: const Key('ielts-later'))
              else
                for (final p in parts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            ieltsPartName(l10n, p.module, p.partNo),
                            style: text.titleSmall,
                          ),
                          for (final g in p.groups)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.sm,
                              ),
                              child: PaperGroupView(
                                group: g,
                                answers: answers,
                                onAnswer: (_, _) {},
                                readOnly: true,
                                flagged: const {},
                                onFlag: (_) {},
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
            ],
            TextButton(
              onPressed: () => context.go('/ielts/my'),
              child: Text(l10n.ieltsTakeBackToTests),
            ),
          ],
        ),
      ),
    );
  }
}

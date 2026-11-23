import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/files/open_file.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/homework/data/homework.dart';
import 'package:instructor_app/features/homework/data/homework_review.dart';
import 'package:instructor_app/features/homework/homework_text.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';

/// A scoring refusal in the web's words, or null.
String? _scoreError(AppLocalizations l10n, ApiException e) {
  final d = e.details is Map ? e.details! as Map : const <String, Object?>{};
  return switch (e.code) {
    'HOMEWORK_SCORE_INVALID' => l10n.homeworkErrorsHOMEWORKSCOREINVALID(
      (d['total'] as num?) ?? 0,
    ),
    'HOMEWORK_STUDENT_NOT_SET' => l10n.homeworkErrorsHOMEWORKSTUDENTNOTSET,
    'HOMEWORK_NOT_LATEST' => l10n.homeworkErrorsHOMEWORKNOTLATEST,
    'HOMEWORK_SESSION_CLOSED' => l10n.homeworkErrorsHOMEWORKSESSIONCLOSED,
    'HOMEWORK_WRONG_STATUS' => l10n.homeworkErrorsHOMEWORKWRONGSTATUS,
    _ => null,
  };
}

String _handInStatus(AppLocalizations l10n, String s) => switch (s) {
  'RETURNED' => l10n.homeworkMyWorkStatusesRETURNED,
  'SCORED' => l10n.homeworkMyWorkStatusesSCORED,
  _ => l10n.homeworkMyWorkStatusesSUBMITTED,
};

String _ratingName(AppLocalizations l10n, String k) => switch (k) {
  'effort' => l10n.homeworkSubmissionsRatingsEffort,
  'on_time' => l10n.homeworkSubmissionsRatingsOnTime,
  _ => l10n.homeworkSubmissionsRatingsNeatness,
};

/// Staff's review of a homework (the web's HomeworkSubmissions): who handed
/// in, was late or is missing; Remind those missing; each student's work
/// with a score, feedback and ratings, or Return for redo; a grid for paper
/// homework; and Publish scores. Not shown for drafts.
class HomeworkReviewSection extends ConsumerStatefulWidget {
  const HomeworkReviewSection({required this.homework, super.key});

  final Homework homework;

  @override
  ConsumerState<HomeworkReviewSection> createState() =>
      _HomeworkReviewSectionState();
}

class _HomeworkReviewSectionState extends ConsumerState<HomeworkReviewSection> {
  HomeworkReview? _latest;
  bool _busy = false;

  Homework get h => widget.homework;
  bool get _scored => h.totalMarks != null;
  bool get _canAct => h.canEdit && h.status == 'PUBLISHED';

  /// Runs [call]; a refusal it knows shows as a message. True when it
  /// worked.
  Future<bool> _call(
    Future<HomeworkReview?> Function() call,
    String done,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final r = await call();
      if (!mounted) return false;
      if (r != null) setState(() => _latest = r);
      messenger.showSnackBar(SnackBar(content: Text(done)));
      return true;
    } catch (e) {
      if (!mounted) return false;
      final known = e is ApiException ? _scoreError(l10n, e) : null;
      if (known != null) {
        messenger.showSnackBar(SnackBar(content: Text(known)));
      } else if (!await handleCommonApiError(
            context,
            e,
            session: ref.read(sessionProvider),
          ) &&
          mounted) {
        messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _save(List<Map<String, Object?>> rows) => _call(
    () => ref.read(homeworkRepositoryProvider).saveScores(h.id, rows),
    context.l10n.homeworkSubmissionsSavedDetail(rows.length),
  );

  Future<void> _remind(int missing) async {
    final l10n = context.l10n;
    var sms = false;
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: Text(l10n.homeworkSubmissionsRemindTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.homeworkSubmissionsRemindDetail(missing)),
              CheckboxListTile(
                key: const Key('remind-sms'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: sms,
                onChanged: (v) => setD(() => sms = v ?? false),
                title: Text(l10n.homeworkSubmissionsSmsGuardians),
                subtitle: Text(l10n.homeworkSubmissionsSmsGuardiansHint),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: Text(l10n.homeworkSubmissionsCancel),
            ),
            FilledButton(
              key: const Key('remind-send'),
              onPressed: () => Navigator.of(d).pop(true),
              child: Text(l10n.homeworkSubmissionsRemindSend),
            ),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final sent = await ref
          .read(homeworkRepositoryProvider)
          .remindMissing(h.id, smsGuardians: sms);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.homeworkSubmissionsReminded(sent.students, sent.sms),
          ),
        ),
      );
    } catch (e) {
      if (mounted &&
          !await handleCommonApiError(
            context,
            e,
            session: ref.read(sessionProvider),
          )) {
        messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish(HomeworkReview r) async {
    final l10n = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.homeworkSubmissionsPublishTitle),
        content: Text(
          l10n.homeworkSubmissionsPublishDetail(r.scored, r.students),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.homeworkSubmissionsCancel),
          ),
          FilledButton(
            key: const Key('publish-scores-confirm'),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.homeworkSubmissionsPublish),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _call(
      () => ref.read(homeworkRepositoryProvider).publishScores(h.id),
      l10n.homeworkSubmissionsPublishedDetail,
    );
  }

  Future<void> _open(ReviewRow row, num? total) async {
    final updated = await Navigator.of(context, rootNavigator: true)
        .push<HomeworkReview>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _ReviewScreen(
              homeworkId: h.id,
              row: row,
              total: total,
              scored: _scored,
              canAct: _canAct,
            ),
          ),
        );
    if (updated != null && mounted) setState(() => _latest = updated);
  }

  @override
  Widget build(BuildContext context) {
    if (h.status == 'DRAFT' || h.status == 'SCHEDULED') {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final loaded = ref.watch(homeworkReviewProvider(h.id));
    final r = _latest ?? loaded.value;
    return AppCard(
      key: const Key('homework-review'),
      child: r != null
          ? _content(r)
          : loaded.hasError
          ? SizedBox(
              height: 220,
              child: ErrorView(
                title: l10n.homeworkSubmissionsLoadFailed,
                retryLabel: l10n.uiErrorRetry,
                onRetry: () => ref.invalidate(homeworkReviewProvider(h.id)),
              ),
            )
          : const LinearProgressIndicator(),
    );
  }

  Widget _content(HomeworkReview r) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final paper = h.type == 'PAPER';
    final missingNow = r.rows.where((x) => x.latest == null).length;
    Widget stat(String key, String label, int v) => Container(
      key: Key('count-$key'),
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: AppRadius.inputAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodySmall?.copyWith(color: colors.inkMuted)),
          Text(OrgTime.number(v, language), style: text.titleMedium),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.homeworkSubmissionsTitle, style: text.titleMedium),
        Text(
          l10n.homeworkSubmissionsSummary(r.handedIn, r.students),
          style: text.bodySmall?.copyWith(color: colors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            stat(
              'students',
              l10n.homeworkSubmissionsCountsStudents,
              r.students,
            ),
            stat(
              'handed-in',
              l10n.homeworkSubmissionsCountsHandedIn,
              r.handedIn,
            ),
            stat('late', l10n.homeworkSubmissionsCountsLate, r.late),
            stat('missing', l10n.homeworkSubmissionsCountsMissing, r.missing),
            stat('scored', l10n.homeworkSubmissionsCountsScored, r.scored),
          ],
        ),
        if (_scored) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            r.scoresPublishedAt != null
                ? l10n.homeworkSubmissionsPublishedOn(
                    OrgTime.dateTime(r.scoresPublishedAt!, language),
                  )
                : l10n.homeworkSubmissionsNotPublished,
            style: text.bodySmall?.copyWith(color: colors.inkMuted),
          ),
        ],
        if (_canAct) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (!paper && missingNow > 0)
                OutlinedButton(
                  key: const Key('remind-missing'),
                  onPressed: _busy ? null : () => _remind(missingNow),
                  child: Text(l10n.homeworkSubmissionsRemind),
                ),
              if (_scored && r.scoresPublishedAt == null && r.scored > 0)
                FilledButton(
                  key: const Key('publish-scores'),
                  onPressed: _busy ? null : () => _publish(r),
                  child: Text(l10n.homeworkSubmissionsPublish),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (r.rows.isEmpty)
          Text(
            l10n.homeworkSubmissionsEmpty,
            style: text.bodyMedium?.copyWith(color: colors.inkMuted),
          )
        else if (paper && _canAct)
          _PaperGrid(
            // A fresh grid when the saved scores change.
            key: ValueKey(
              r.rows
                  .map((x) => '${x.score?.rawScore}/${x.score?.feedback}')
                  .join(','),
            ),
            review: r,
            scored: _scored,
            busy: _busy,
            onSave: _save,
          )
        else
          for (final row in r.rows)
            _RowTile(
              row: row,
              scored: _scored,
              paper: paper,
              onOpen: row.latest == null
                  ? null
                  : () => _open(row, r.totalMarks),
            ),
      ],
    );
  }
}

/// The student's state: handed in (late), returned, scored, or missing.
class _StatePills extends StatelessWidget {
  const _StatePills(this.row);

  final ReviewRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final latest = row.latest;
    if (latest == null) {
      return StatusPill(
        label: l10n.homeworkSubmissionsMissing,
        tone: row.score?.isMissing == true
            ? StatusTone.danger
            : StatusTone.neutral,
      );
    }
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        StatusPill(
          label: _handInStatus(l10n, latest.status),
          tone: latest.status == 'RETURNED'
              ? StatusTone.warning
              : StatusTone.success,
        ),
        if (latest.isLate)
          StatusPill(
            label: l10n.homeworkMyWorkLate(latest.lateMinutes ?? 0),
            tone: StatusTone.warning,
          ),
      ],
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.row,
    required this.scored,
    required this.paper,
    this.onOpen,
  });

  final ReviewRow row;
  final bool scored;
  final bool paper;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final score = row.score == null ? null : scoreText(row.score!, language);
    return ListTile(
      key: Key('row-${row.studentId}'),
      contentPadding: EdgeInsets.zero,
      onTap: onOpen,
      title: Text(row.label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xs),
          if (!paper || row.score?.isMissing == true) _StatePills(row),
          if (row.latest?.submittedAt != null)
            Text(
              '${OrgTime.dateTime(row.latest!.submittedAt!, language)}'
              ' · ${l10n.homeworkSubmissionsVersions}: '
              '${OrgTime.number(row.versions, language)}',
              style: text.bodySmall?.copyWith(color: colors.inkMuted),
            ),
          if (paper && row.score?.feedback != null)
            Text(row.score!.feedback!, style: text.bodySmall),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (scored) Text(score ?? '—', style: text.titleSmall),
          if (onOpen != null) const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

/// The three 1–5 ratings (optional).
class _Ratings extends StatelessWidget {
  const _Ratings({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.keyPrefix = 'rating',
  });

  final Map<String, int> value;
  final ValueChanged<Map<String, int>> onChanged;
  final bool enabled;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final k in ratingKeys)
          SizedBox(
            width: 140,
            child: DropdownButtonFormField<int?>(
              key: Key('$keyPrefix-$k'),
              initialValue: value[k],
              isExpanded: true,
              decoration: InputDecoration(labelText: _ratingName(l10n, k)),
              items: [
                const DropdownMenuItem<int?>(child: Text('—')),
                for (var n = 1; n <= 5; n++)
                  DropdownMenuItem<int?>(
                    value: n,
                    child: Text(OrgTime.number(n, language)),
                  ),
              ],
              onChanged: enabled
                  ? (v) {
                      final next = {...value};
                      v == null ? next.remove(k) : next[k] = v;
                      onChanged(next);
                    }
                  : null,
            ),
          ),
      ],
    );
  }
}

/// One student's versions, with the score form and Return for redo (the
/// web's review drawer). Returns the review as it is after a change.
class _ReviewScreen extends ConsumerStatefulWidget {
  const _ReviewScreen({
    required this.homeworkId,
    required this.row,
    required this.total,
    required this.scored,
    required this.canAct,
  });

  final String homeworkId;
  final ReviewRow row;
  final num? total;
  final bool scored;
  final bool canAct;

  @override
  ConsumerState<_ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<_ReviewScreen> {
  late ScoreDraft _draft = ScoreDraft.of(widget.row);
  late final _score = TextEditingController(text: _draft.raw);
  late final _feedback = TextEditingController(text: _draft.feedback);
  late final Future<List<HandIn>> _versions = ref
      .read(homeworkRepositoryProvider)
      .versions(widget.homeworkId, widget.row.latest!.id!);
  bool _busy = false;
  String? _problem;

  @override
  void dispose() {
    _score.dispose();
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _run(Future<HomeworkReview> Function() call) async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final r = await call();
      if (mounted) Navigator.of(context).pop(r);
    } catch (e) {
      if (!mounted) return;
      final known = e is ApiException ? _scoreError(l10n, e) : null;
      if (known != null) {
        setState(() => _problem = known);
      } else if (!await handleCommonApiError(
            context,
            e,
            session: ref.read(sessionProvider),
          ) &&
          mounted) {
        setState(() => _problem = apiErrorText(l10n, e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _return() async {
    // The dialog owns its text box and gives back the note (null: cancel).
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const _ReturnDialog(),
    );
    if (note == null) return;
    await _run(
      () => ref
          .read(homeworkRepositoryProvider)
          .returnForRedo(widget.homeworkId, widget.row.latest!.id!, note: note),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final row = widget.row;
    final invalid = widget.scored && scoreProblem(_draft.raw, widget.total);
    return Scaffold(
      appBar: AppBar(title: Text(row.name)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              FutureBuilder<List<HandIn>>(
                future: _versions,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Text(l10n.homeworkSubmissionsLoadFailed);
                  }
                  if (!snap.hasData) return const LinearProgressIndicator();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final v in snap.data!)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: AppCard(
                            key: Key('version-${v.version}'),
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: AppSpacing.sm,
                                  runSpacing: AppSpacing.xs,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      l10n.homeworkMyWorkVersion(v.version),
                                      style: text.titleSmall,
                                    ),
                                    if (v.submittedAt != null)
                                      Text(
                                        OrgTime.dateTime(
                                          v.submittedAt!,
                                          language,
                                        ),
                                        style: text.bodySmall?.copyWith(
                                          color: colors.inkMuted,
                                        ),
                                      ),
                                    StatusPill(
                                      label: _handInStatus(l10n, v.status),
                                      tone: v.status == 'RETURNED'
                                          ? StatusTone.warning
                                          : StatusTone.neutral,
                                    ),
                                    if (v.isLate)
                                      StatusPill(
                                        label: l10n.homeworkMyWorkLate(
                                          v.lateMinutes ?? 0,
                                        ),
                                        tone: StatusTone.warning,
                                      ),
                                  ],
                                ),
                                if (v.text != null && v.text!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: AppSpacing.xs,
                                    ),
                                    child: SelectableText(
                                      v.text!,
                                      style: text.bodyMedium,
                                    ),
                                  ),
                                for (final f in v.files)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      f.isImage
                                          ? Icons.image_outlined
                                          : Icons.insert_drive_file_outlined,
                                    ),
                                    title: Text(
                                      f.name ?? l10n.homeworkMyWorkFile,
                                    ),
                                    trailing: const Icon(Icons.open_in_new),
                                    onTap: () => openFile(context, ref, f.id),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              if ((row.score?.penalty ?? 0) > 0)
                Text(
                  l10n.homeworkSubmissionsPenaltyTaken(row.score!.penalty),
                  style: text.bodySmall?.copyWith(color: colors.inkMuted),
                ),
              if (widget.canAct) ...[
                const Divider(height: AppSpacing.xl),
                if (widget.scored)
                  TextField(
                    key: const Key('review-score'),
                    controller: _score,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (v) =>
                        setState(() => _draft = _draft.copyWith(raw: v)),
                    decoration: InputDecoration(
                      labelText: l10n.homeworkSubmissionsScore,
                      suffixText: widget.total == null
                          ? null
                          : '/ ${OrgTime.number(widget.total!, language)}',
                      helperText: row.latest?.isLate == true
                          ? l10n.homeworkSubmissionsLateHint
                          : null,
                      helperMaxLines: 3,
                      errorText: invalid
                          ? l10n.homeworkSubmissionsScoreInvalid(
                              widget.total ?? 0,
                            )
                          : null,
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const Key('review-feedback'),
                  controller: _feedback,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 5,
                  onChanged: (v) =>
                      setState(() => _draft = _draft.copyWith(feedback: v)),
                  decoration: InputDecoration(
                    labelText: l10n.homeworkSubmissionsFeedback,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _Ratings(
                  value: _draft.ratings,
                  enabled: !_busy,
                  onChanged: (v) =>
                      setState(() => _draft = _draft.copyWith(ratings: v)),
                ),
                if (_problem != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      _problem!,
                      key: const Key('review-problem'),
                      style: text.bodySmall?.copyWith(color: colors.danger),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (row.latest?.status != 'RETURNED')
                      OutlinedButton(
                        key: const Key('review-return'),
                        onPressed: _busy ? null : _return,
                        child: Text(l10n.homeworkSubmissionsReturn),
                      ),
                    FilledButton(
                      key: const Key('review-save'),
                      onPressed: _busy || invalid
                          ? null
                          : () => _run(
                              () => ref
                                  .read(homeworkRepositoryProvider)
                                  .saveScores(widget.homeworkId, [
                                    _draft.toJson(
                                      row.studentId,
                                      scored: widget.scored,
                                    ),
                                  ]),
                            ),
                      child: Text(l10n.homeworkSubmissionsSaveScore),
                    ),
                  ],
                ),
              ] else if (row.score != null &&
                  scoreText(row.score!, language) != null)
                Text(scoreText(row.score!, language)!, style: text.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Return for redo": an optional note; returns it, or null to cancel.
class _ReturnDialog extends StatefulWidget {
  const _ReturnDialog();

  @override
  State<_ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends State<_ReturnDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.homeworkSubmissionsReturnTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.homeworkSubmissionsReturnDetail),
          TextField(
            key: const Key('return-note'),
            controller: _note,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: l10n.homeworkSubmissionsReturnNote,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.homeworkSubmissionsCancel),
        ),
        FilledButton(
          key: const Key('return-confirm'),
          onPressed: () => Navigator.of(context).pop(_note.text),
          child: Text(l10n.homeworkSubmissionsReturn),
        ),
      ],
    );
  }
}

/// Paper homework: every student's score, remark, ratings and "not handed
/// in", saved together (only the changed rows are sent).
class _PaperGrid extends StatefulWidget {
  const _PaperGrid({
    required this.review,
    required this.scored,
    required this.busy,
    required this.onSave,
    super.key,
  });

  final HomeworkReview review;
  final bool scored;
  final bool busy;
  final Future<bool> Function(List<Map<String, Object?>> rows) onSave;

  @override
  State<_PaperGrid> createState() => _PaperGridState();
}

class _PaperGridState extends State<_PaperGrid> {
  late final Map<String, ScoreDraft> _drafts = {
    for (final r in widget.review.rows) r.studentId: ScoreDraft.of(r),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final total = widget.review.totalMarks;
    final changed = [
      for (final r in widget.review.rows)
        if (!_drafts[r.studentId]!.same(ScoreDraft.of(r))) r,
    ];
    final invalid =
        widget.scored &&
        widget.review.rows.any(
          (r) => scoreProblem(_drafts[r.studentId]!.raw, total),
        );
    void change(String id, ScoreDraft d) => setState(() => _drafts[id] = d);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.homeworkSubmissionsPaperHint,
          style: text.bodySmall?.copyWith(color: colors.inkMuted),
        ),
        for (final r in widget.review.rows)
          Padding(
            key: Key('paper-${r.studentId}'),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(r.label, style: text.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.scored) ...[
                      SizedBox(
                        width: 120,
                        child: TextFormField(
                          key: Key('paper-score-${r.studentId}'),
                          initialValue: _drafts[r.studentId]!.raw,
                          enabled: !_drafts[r.studentId]!.missing,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (v) => change(
                            r.studentId,
                            _drafts[r.studentId]!.copyWith(raw: v),
                          ),
                          decoration: InputDecoration(
                            labelText: l10n.homeworkSubmissionsScore,
                            suffixText: total == null
                                ? null
                                : '/ ${OrgTime.number(total, language)}',
                            errorText:
                                scoreProblem(_drafts[r.studentId]!.raw, total)
                                ? l10n.homeworkSubmissionsScoreInvalid(
                                    total ?? 0,
                                  )
                                : null,
                            errorMaxLines: 3,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(
                      child: TextFormField(
                        key: Key('paper-remark-${r.studentId}'),
                        initialValue: _drafts[r.studentId]!.feedback,
                        maxLength: 2000,
                        onChanged: (v) => change(
                          r.studentId,
                          _drafts[r.studentId]!.copyWith(feedback: v),
                        ),
                        decoration: InputDecoration(
                          labelText: l10n.homeworkSubmissionsRemark,
                          counterText: '',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                _Ratings(
                  keyPrefix: 'paper-rating-${r.studentId}',
                  value: _drafts[r.studentId]!.ratings,
                  enabled: !widget.busy,
                  onChanged: (v) => change(
                    r.studentId,
                    _drafts[r.studentId]!.copyWith(ratings: v),
                  ),
                ),
                CheckboxListTile(
                  key: Key('paper-missing-${r.studentId}'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _drafts[r.studentId]!.missing,
                  onChanged: (v) => change(
                    r.studentId,
                    _drafts[r.studentId]!.copyWith(missing: v ?? false),
                  ),
                  title: Text(l10n.homeworkSubmissionsNotHandedIn),
                ),
                const Divider(),
              ],
            ),
          ),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          children: [
            if (changed.isNotEmpty)
              Text(
                l10n.homeworkSubmissionsUnsaved(changed.length),
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              ),
            FilledButton(
              key: const Key('paper-save'),
              onPressed: widget.busy || invalid || changed.isEmpty
                  ? null
                  : () => widget.onSave([
                      for (final r in changed)
                        _drafts[r.studentId]!.toJson(
                          r.studentId,
                          scored: widget.scored,
                        ),
                    ]),
              child: Text(l10n.homeworkSubmissionsSaveAll),
            ),
          ],
        ),
      ],
    );
  }
}

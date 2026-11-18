import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';
import 'package:instructor_app/features/tests/data/grading.dart';

/// Where a test's grading opens (the web's path).
String gradingRoute(String examId) => '/grading/details/$examId';

String _status(AppLocalizations l10n, String s) => switch (s) {
  'GRADED' => l10n.gradingStatusGRADED,
  'PUBLISHED' => l10n.gradingStatusPUBLISHED,
  _ => l10n.gradingStatusNEEDSGRADING,
};

StatusTone _statusTone(String s) => switch (s) {
  'GRADED' => StatusTone.info,
  'PUBLISHED' => StatusTone.success,
  _ => StatusTone.warning,
};

/// The web's /grading: the teacher's ended tests with how many hand-ins are
/// marked, by grading status; each opens its submissions.
class GradingListScreen extends ConsumerStatefulWidget {
  const GradingListScreen({super.key});

  @override
  ConsumerState<GradingListScreen> createState() => _GradingListScreenState();
}

class _GradingListScreenState extends ConsumerState<GradingListScreen> {
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final list = ref.watch(gradingListProvider(_filter));
    String n(num v) => OrgTime.number(v, language);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(gradingListProvider(_filter));
            await ref
                .read(gradingListProvider(_filter).future)
                .then<void>((_) {}, onError: (Object _) {});
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(l10n.gradingTitle, style: text.headlineSmall),
              Text(
                l10n.gradingIntro,
                style: text.bodyMedium?.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final (value, label) in [
                    (null, l10n.gradingFilterALL),
                    ('NEEDS_GRADING', l10n.gradingFilterNEEDSGRADING),
                    ('GRADED', l10n.gradingFilterGRADED),
                    ('PUBLISHED', l10n.gradingFilterPUBLISHED),
                  ])
                    ChoiceChip(
                      key: Key('grading-filter-${value ?? 'ALL'}'),
                      label: Text(label),
                      selected: _filter == value,
                      onSelected: (_) => setState(() => _filter = value),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              ...list.when(
                loading: () => [
                  SizedBox(
                    height: 220,
                    child: LoadingView(semanticsLabel: l10n.gradingTitle),
                  ),
                ],
                error: (e, _) => [
                  SizedBox(
                    height: 300,
                    child: ErrorView(
                      title: l10n.gradingDetailsLoadFailed,
                      retryLabel: l10n.uiErrorRetry,
                      onRetry: () =>
                          ref.invalidate(gradingListProvider(_filter)),
                    ),
                  ),
                ],
                data: (items) => items.isEmpty
                    ? [
                        SizedBox(
                          height: 260,
                          child: EmptyView(
                            icon: Icons.fact_check_outlined,
                            title: l10n.gradingEmpty,
                            message: l10n.gradingEmptyDetail,
                          ),
                        ),
                      ]
                    : [
                        for (final g in items) ...[
                          AppCard(
                            key: Key('grading-${g.id}'),
                            onTap: () => context.push(gradingRoute(g.id)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        g.name,
                                        style: text.titleMedium,
                                      ),
                                    ),
                                    StatusPill(
                                      label: _status(l10n, g.status),
                                      tone: _statusTone(g.status),
                                    ),
                                  ],
                                ),
                                Text(
                                  [
                                    ?g.subject,
                                    ?g.className,
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                  style: text.bodySmall?.copyWith(
                                    color: colors.inkMuted,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  [
                                    '${l10n.gradingCardSubmissions}: ${n(g.submitted)}',
                                    '${l10n.gradingCardGraded}: ${n(g.graded)}',
                                    if (g.pending > 0)
                                      l10n.gradingCardPending(g.pending),
                                    if (g.averagePercent != null)
                                      '${n(g.averagePercent!.round())}%',
                                  ].join(' · '),
                                  style: text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A test's grading (the web's /grading/details/:id): its counts, every
/// submission with its marking state and score, and Publish results once
/// all are marked (asked first). A submission opens for marking.
class GradingDetailScreen extends ConsumerStatefulWidget {
  const GradingDetailScreen({required this.examId, super.key});

  final String examId;

  @override
  ConsumerState<GradingDetailScreen> createState() =>
      _GradingDetailScreenState();
}

class _GradingDetailScreenState extends ConsumerState<GradingDetailScreen> {
  bool _busy = false;

  Future<void> _publish() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.gradingDetailsPublishTitle),
        content: Text(l10n.gradingDetailsPublishDetail),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.uiCancel),
          ),
          FilledButton(
            key: const Key('publish-confirm'),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.gradingDetailsPublish),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(gradingRepositoryProvider).publish(widget.examId);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.gradingDetailsPublishedToast)),
      );
      ref
        ..invalidate(gradingSummaryProvider(widget.examId))
        ..invalidate(gradingListProvider);
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

  Future<void> _open(GradingSubmission s) async {
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            _SubmissionScreen(examId: widget.examId, submissionId: s.id),
      ),
    );
    if (saved == true) {
      ref
        ..invalidate(gradingSummaryProvider(widget.examId))
        ..invalidate(gradingListProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final summary = ref.watch(gradingSummaryProvider(widget.examId));
    String n(num v) => OrgTime.number(v, language);
    Widget stat(String label, int v) => Container(
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
          Text(n(v), style: text.titleMedium),
        ],
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: summary.when(
          skipLoadingOnReload: true,
          loading: () => LoadingView(semanticsLabel: l10n.gradingDetailsTitle),
          error: (e, _) => ErrorView(
            title: l10n.gradingDetailsLoadFailed,
            retryLabel: l10n.uiErrorRetry,
            onRetry: () =>
                ref.invalidate(gradingSummaryProvider(widget.examId)),
          ),
          data: (s) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(gradingSummaryProvider(widget.examId));
              await ref
                  .read(gradingSummaryProvider(widget.examId).future)
                  .then<void>((_) {}, onError: (Object _) {});
            },
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(s.name, style: text.headlineSmall),
                Text(
                  [?s.subject, ?s.className].join(' · '),
                  style: text.bodySmall?.copyWith(color: colors.inkMuted),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: StatusPill(
                    label: _status(l10n, s.status),
                    tone: _statusTone(s.status),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    stat(l10n.gradingDetailsTotalStudents, s.students),
                    stat(l10n.gradingDetailsSubmissions, s.submissions),
                    stat(l10n.gradingDetailsPending, s.pending),
                    stat(l10n.gradingDetailsGraded, s.graded),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (s.published)
                  Text(
                    l10n.gradingDetailsPublished,
                    key: const Key('results-published'),
                    style: text.bodyMedium?.copyWith(color: colors.success),
                  )
                else ...[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton(
                      key: const Key('results-publish'),
                      onPressed: _busy || !s.canPublish ? null : _publish,
                      child: Text(l10n.gradingDetailsPublish),
                    ),
                  ),
                  if (!s.canPublish)
                    Text(
                      l10n.gradingDetailsPublishHint,
                      style: text.bodySmall?.copyWith(color: colors.inkMuted),
                    ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Text(l10n.gradingSubmissionsTitle, style: text.titleMedium),
                if (s.rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    child: Text(
                      l10n.gradingSubmissionsEmpty,
                      style: text.bodyMedium?.copyWith(color: colors.inkMuted),
                    ),
                  )
                else
                  for (final r in s.rows)
                    ListTile(
                      key: Key('submission-${r.id}'),
                      contentPadding: EdgeInsets.zero,
                      onTap: () => _open(r),
                      title: Text(r.name ?? l10n.gradingSubmissionsAnonymous),
                      subtitle: Text(
                        [
                          ?r.contact,
                          if (r.submittedAt != null)
                            OrgTime.dateTime(r.submittedAt!, language),
                          if (r.flags > 0)
                            '${l10n.gradingSubmissionsViolations}: ${n(r.flags)}',
                        ].join(' · '),
                        style: text.bodySmall?.copyWith(color: colors.inkMuted),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          StatusPill(
                            label: r.gradingStatus == 'GRADED'
                                ? l10n.gradingSubmissionsGradeStatusGRADED
                                : l10n.gradingSubmissionsGradeStatusPENDING,
                            tone: r.gradingStatus == 'GRADED'
                                ? StatusTone.success
                                : StatusTone.warning,
                          ),
                          if (r.score != null)
                            Text(
                              '${n(r.score!)}/${n(r.maxScore ?? 0)}',
                              style: text.bodySmall,
                            ),
                        ],
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

/// One submission: every answer, with marks and feedback for the written
/// ones (0 to the question's points); objective answers show as right or
/// wrong. Returns true once saved.
class _SubmissionScreen extends ConsumerStatefulWidget {
  const _SubmissionScreen({required this.examId, required this.submissionId});

  final String examId;
  final String submissionId;

  @override
  ConsumerState<_SubmissionScreen> createState() => _SubmissionScreenState();
}

class _SubmissionScreenState extends ConsumerState<_SubmissionScreen> {
  late final _key = (examId: widget.examId, id: widget.submissionId);
  final _marks = <String, TextEditingController>{};
  final _feedback = <String, TextEditingController>{};
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [..._marks.values, ..._feedback.values]) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _marksFor(GradedQuestion q) => _marks.putIfAbsent(
    q.id,
    () => TextEditingController(
      text: q.marks == 0 && q.correct == null ? '' : _plain(q.marks),
    ),
  );

  TextEditingController _feedbackFor(GradedQuestion q) => _feedback.putIfAbsent(
    q.id,
    () => TextEditingController(text: q.feedback ?? ''),
  );

  static String _plain(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  /// Why a mark is not allowed, or null.
  String? _problem(GradedQuestion q) {
    final v = _marks[q.id]?.text.trim().replaceAll(',', '.') ?? '';
    if (v.isEmpty) return null;
    final m = num.tryParse(v);
    if (m == null || m < 0) return context.l10n.gradingAnswerBelowZero;
    if (m > q.points) return context.l10n.gradingAnswerAboveMax;
    return null;
  }

  Future<void> _save(SubmissionForGrading s) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final grades = [
      for (final q in s.questions)
        if (q.manual && (_marks[q.id]?.text.trim().isNotEmpty ?? false))
          (
            questionId: q.id,
            marks: num.parse(_marks[q.id]!.text.trim().replaceAll(',', '.')),
            feedback: _feedback[q.id]?.text ?? '',
          ),
    ];
    setState(() => _busy = true);
    try {
      await ref
          .read(gradingRepositoryProvider)
          .save(widget.examId, widget.submissionId, grades);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.gradingModalSavedToast)),
      );
      navigator.pop(true);
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sub = ref.watch(submissionForGradingProvider(_key));
    return Scaffold(
      appBar: AppBar(title: Text(sub.value?.name ?? l10n.gradingModalGrade)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: sub.when(
            loading: () => LoadingView(semanticsLabel: l10n.gradingModalGrade),
            error: (e, _) => ErrorView(
              title: l10n.gradingDetailsLoadFailed,
              retryLabel: l10n.uiErrorRetry,
              onRetry: () => ref.invalidate(submissionForGradingProvider(_key)),
            ),
            data: _page,
          ),
        ),
      ),
    );
  }

  Widget _page(SubmissionForGrading s) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    String n(num v) => OrgTime.number(v, language);
    final anyProblem = s.questions.any((q) => q.manual && _problem(q) != null);
    if (s.questions.isEmpty) {
      return EmptyView(
        icon: Icons.description_outlined,
        title: l10n.gradingModalEmpty,
      );
    }
    // A passage shows once, above its first question.
    bool startsPassage(int i) =>
        s.questions[i].passage != null &&
        (i == 0 || s.questions[i - 1].passage != s.questions[i].passage);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          l10n.gradingModalScore('${n(s.score)}/${n(s.maxScore)}'),
          style: text.titleMedium,
        ),
        if (s.manualTotal > 0)
          Text(
            l10n.gradingModalManualProgress(s.manualGraded, s.manualTotal),
            style: text.bodySmall?.copyWith(color: colors.inkMuted),
          ),
        const SizedBox(height: AppSpacing.md),
        for (final (i, q) in s.questions.indexed) ...[
          if (startsPassage(i)) ...[
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.gradingModalPassage, style: text.titleSmall),
                  Text(q.passage!, style: text.bodyMedium),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          AppCard(
            key: Key('question-${q.id}'),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${n(i + 1)}. ${q.text}', style: text.titleSmall),
                Text(
                  l10n.gradingAnswerMaxMarks(q.points),
                  style: text.bodySmall?.copyWith(color: colors.inkMuted),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (q.manual) ...[
                  Text(
                    l10n.gradingAnswerStudentAnswer,
                    style: text.labelMedium,
                  ),
                  SelectableText(
                    (q.answer ?? '').trim().isEmpty
                        ? l10n.gradingAnswerNone
                        : q.answer!,
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    key: Key('marks-${q.id}'),
                    controller: _marksFor(q),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: l10n.gradingAnswerScoreFor(i + 1),
                      suffixText: '/ ${n(q.points)}',
                      errorText: _problem(q),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    key: Key('feedback-${q.id}'),
                    controller: _feedbackFor(q),
                    maxLength: 2000,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: l10n.gradingAnswerExplanation,
                      hintText: l10n.gradingAnswerExplanationPlaceholder,
                    ),
                  ),
                ] else ...[
                  if (q.chosen.isNotEmpty)
                    Text(
                      q.chosen.map((c) => q.options[c] ?? c).join(', '),
                      style: text.bodyMedium,
                    ),
                  Row(
                    children: [
                      StatusPill(
                        label: q.chosen.isEmpty && q.correct != true
                            ? l10n.gradingAnswerNone
                            : (q.correct == true
                                  ? l10n.gradingAnswerCorrect
                                  : l10n.gradingAnswerIncorrect),
                        tone: q.correct == true
                            ? StatusTone.success
                            : StatusTone.danger,
                      ),
                      const Spacer(),
                      Text(
                        '${n(q.marks)}/${n(q.points)}',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (s.manualTotal > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              key: const Key('grades-save'),
              onPressed: _busy || anyProblem ? null : () => _save(s),
              child: Text(
                _busy ? l10n.gradingModalSubmitting : l10n.gradingModalSubmit,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

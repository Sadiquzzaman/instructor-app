import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/plan/data/feature_names.g.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';
import 'package:instructor_app/features/tests/data/integrity.dart';
import 'package:instructor_app/features/tests/screens/monitor_screen.dart';
import 'package:instructor_app/features/tests/screens/teacher_tests_screens.dart';

/// A check's name from the plan catalogue, or "Other" (the web's
/// `useCheckName`).
String _checkName(AppLocalizations l10n, String check) =>
    featureName(l10n, check) ?? l10n.integrityOtherCheck;

String _result(AppLocalizations l10n, String s) => switch (s) {
  'SUBMITTED' => l10n.integrityStatusSUBMITTED,
  'AUTO_SUBMITTED' => l10n.integrityStatusAUTOSUBMITTED,
  'DISQUALIFIED' => l10n.integrityStatusDISQUALIFIED,
  'IN_PROGRESS' => l10n.integrityStatusINPROGRESS,
  _ => s,
};

StatusTone _resultTone(String s) => switch (s) {
  'SUBMITTED' => StatusTone.success,
  'DISQUALIFIED' => StatusTone.danger,
  'IN_PROGRESS' => StatusTone.info,
  _ => StatusTone.neutral,
};

String _decision(AppLocalizations l10n, String d) => switch (d) {
  'REINSTATE' => l10n.integrityDecisionREINSTATE,
  'RETAKE' => l10n.integrityDecisionRETAKE,
  _ => l10n.integrityDecisionCONFIRM,
};

/// The integrity report (the web's /tests/:id/integrity): flags by check,
/// every student who took the test with result, score, flags and the
/// latest review, most flagged first. A student opens their report and the
/// teacher's decision: reinstate, retake or confirm, with a reason.
/// Printing stays on the web.
class IntegrityScreen extends ConsumerWidget {
  const IntegrityScreen({required this.examId, super.key});

  final String examId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final name = ref.watch(teacherTestProvider(examId)).value?.name;
    final report = ref.watch(integrityReportProvider(examId));
    String n(num v) => OrgTime.number(v, language);
    Widget stat(String label, int v) => Container(
      constraints: const BoxConstraints(minWidth: 120),
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
        constraints: const BoxConstraints(maxWidth: 960),
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(integrityReportProvider(examId));
            await ref
                .read(integrityReportProvider(examId).future)
                .then<void>((_) {}, onError: (Object _) {});
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(l10n.integrityTitle, style: text.headlineSmall),
              if (name != null)
                Text(
                  name,
                  style: text.bodySmall?.copyWith(color: colors.inkMuted),
                ),
              const SizedBox(height: AppSpacing.md),
              ...report.when(
                loading: () => [
                  SizedBox(
                    height: 220,
                    child: LoadingView(semanticsLabel: l10n.integrityTitle),
                  ),
                ],
                error: (e, _) => [
                  SizedBox(
                    height: 300,
                    child: ErrorView(
                      title: e is ApiException && e.statusCode == 403
                          ? l10n.integrityNotAllowed
                          : l10n.integrityLoadFailed,
                      retryLabel: l10n.uiErrorRetry,
                      onRetry: () =>
                          ref.invalidate(integrityReportProvider(examId)),
                    ),
                  ),
                ],
                data: (r) => [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      stat(l10n.integrityStudents, r.students),
                      stat(l10n.integrityFlagged, r.flagged),
                      stat(l10n.integrityDisqualified, r.disqualified),
                      stat(l10n.integrityReviewed, r.reviewed),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(l10n.integrityByCheck, style: text.titleMedium),
                        if (r.byCheck.isEmpty)
                          Text(
                            l10n.integrityNoFlags,
                            style: text.bodySmall?.copyWith(
                              color: colors.inkMuted,
                            ),
                          )
                        else
                          for (final c in r.byCheck)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.xs,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(_checkName(l10n, c.check)),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  // Wraps on a phone in Bangla.
                                  Flexible(
                                    child: Text(
                                      l10n.integrityCheckCount(
                                        c.count,
                                        c.students,
                                      ),
                                      textAlign: TextAlign.end,
                                      style: text.bodySmall?.copyWith(
                                        color: colors.inkMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (r.rows.isEmpty)
                    Text(
                      l10n.integrityEmpty,
                      style: text.bodyMedium?.copyWith(color: colors.inkMuted),
                    )
                  else
                    for (final row in r.rows)
                      AppCard(
                        key: Key('integrity-${row.studentId}'),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        onTap: () => Navigator.of(context, rootNavigator: true)
                            .push<void>(
                              MaterialPageRoute(
                                fullscreenDialog: true,
                                builder: (_) => _StudentIntegrityScreen(
                                  examId: examId,
                                  row: row,
                                ),
                              ),
                            ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(row.name, style: text.titleSmall),
                                ),
                                StatusPill(
                                  label: _result(l10n, row.status),
                                  tone: _resultTone(row.status),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              [
                                '${l10n.integrityScore}: ${row.score == null ? '—' : l10n.integrityScoreOf(row.score!, row.maxScore ?? 0)}',
                                '${l10n.integrityFlags}: ${n(row.flags)}',
                                if (row.lastDecision != null)
                                  '${l10n.integrityReview}: ${_decision(l10n, row.lastDecision!)}',
                              ].join(' · '),
                              style: text.bodySmall,
                            ),
                            if (row.checks.isNotEmpty)
                              Text(
                                row.checks
                                    .take(2)
                                    .map(
                                      (c) =>
                                          '${_checkName(l10n, c.check)} (${n(c.count)})',
                                    )
                                    .join(', '),
                                style: text.bodySmall?.copyWith(
                                  color: colors.inkMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One student's report and the review form.
class _StudentIntegrityScreen extends ConsumerStatefulWidget {
  const _StudentIntegrityScreen({required this.examId, required this.row});

  final String examId;
  final IntegrityRow row;

  @override
  ConsumerState<_StudentIntegrityScreen> createState() =>
      _StudentIntegrityScreenState();
}

class _StudentIntegrityScreenState
    extends ConsumerState<_StudentIntegrityScreen> {
  String? _picked;
  final _reason = TextEditingController();
  bool _busy = false;

  late final _key = (examId: widget.examId, studentId: widget.row.studentId);

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(apiClientProvider)
          .post(
            '/exams/${widget.examId}/proctoring/students/${widget.row.studentId}/review',
            data: {'decision': _picked, 'reason': _reason.text.trim()},
          );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.integritySaved)));
      setState(() {
        _picked = null;
        _reason.clear();
      });
      ref
        ..invalidate(studentIntegrityProvider(_key))
        ..invalidate(integrityReportProvider(widget.examId));
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
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final report = ref.watch(studentIntegrityProvider(_key));
    final row = widget.row;
    final finished = row.status != 'IN_PROGRESS';
    final options = [
      if (row.status == 'DISQUALIFIED') 'REINSTATE',
      'RETAKE',
      'CONFIRM',
    ];
    String hint(String d) => switch (d) {
      'REINSTATE' => l10n.integrityDecisionHintREINSTATE,
      'RETAKE' => l10n.integrityDecisionHintRETAKE,
      _ => l10n.integrityDecisionHintCONFIRM,
    };
    return Scaffold(
      appBar: AppBar(title: Text(row.name)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: report.when(
            skipLoadingOnReload: true,
            loading: () => LoadingView(semanticsLabel: l10n.integrityTitle),
            error: (_, _) => ErrorView(
              title: l10n.integrityLoadFailed,
              retryLabel: l10n.uiErrorRetry,
              onRetry: () => ref.invalidate(studentIntegrityProvider(_key)),
            ),
            data: (r) => ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: StatusPill(
                    label: _result(l10n, r.status),
                    tone: _resultTone(r.status),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${l10n.integrityScore}: ${r.score == null ? '—' : l10n.integrityScoreOf(r.score!, r.maxScore ?? 0)}',
                  style: text.bodyMedium,
                ),
                if (r.why != null && r.why!.isNotEmpty)
                  Text(
                    '${l10n.integrityWhy}: ${r.why}',
                    style: text.bodyMedium,
                  ),
                const SizedBox(height: AppSpacing.md),
                Text(l10n.integrityByCheck, style: text.titleSmall),
                if (r.checks.isEmpty)
                  Text(
                    l10n.integrityNoFlags,
                    style: text.bodySmall?.copyWith(color: colors.inkMuted),
                  )
                else
                  for (final c in r.checks)
                    Row(
                      children: [
                        Expanded(child: Text(_checkName(l10n, c.check))),
                        Text(OrgTime.number(c.count, language)),
                      ],
                    ),
                const SizedBox(height: AppSpacing.md),
                Text(l10n.integrityTimeline, style: text.titleSmall),
                if (r.timeline.isEmpty)
                  Text(
                    l10n.integrityNoFlags,
                    style: text.bodySmall?.copyWith(color: colors.inkMuted),
                  )
                else
                  for (final e in r.timeline)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 72,
                            child: Text(
                              e.at == null ? '' : OrgTime.time(e.at!, language),
                              style: text.bodySmall?.copyWith(
                                color: colors.inkMuted,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${monitorEventText(l10n, e.type)}'
                              '${e.type.startsWith('teacher-') && (e.message ?? '').isNotEmpty ? ': ${e.message}' : ''}',
                            ),
                          ),
                        ],
                      ),
                    ),
                if (r.reviews.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(l10n.integrityHistory, style: text.titleSmall),
                  for (final v in r.reviews)
                    AppCard(
                      key: Key('review-${v.id}'),
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_decision(l10n, v.decision)}'
                            '${v.at == null ? '' : ' · ${OrgTime.dateTime(v.at!, language)}'}',
                            style: text.titleSmall,
                          ),
                          Text(
                            l10n.integrityDecidedBy(v.by ?? '—', v.reason),
                            style: text.bodySmall?.copyWith(
                              color: colors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const Divider(height: AppSpacing.xl),
                if (!finished)
                  Text(
                    l10n.integrityWriting,
                    style: text.bodySmall?.copyWith(color: colors.inkMuted),
                  )
                else ...[
                  Text(l10n.integrityDecide, style: text.titleSmall),
                  RadioGroup<String>(
                    groupValue: _picked,
                    onChanged: (v) => setState(() => _picked = v),
                    child: Column(
                      children: [
                        for (final d in options)
                          RadioListTile<String>(
                            key: Key('decision-$d'),
                            contentPadding: EdgeInsets.zero,
                            value: d,
                            title: Text(_decision(l10n, d)),
                            subtitle: Text(hint(d)),
                          ),
                      ],
                    ),
                  ),
                  TextField(
                    key: const Key('integrity-reason'),
                    controller: _reason,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 4,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: l10n.integrityReason,
                      helperText: l10n.integrityReasonHint,
                      helperMaxLines: 3,
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton(
                      key: const Key('integrity-save'),
                      onPressed:
                          _busy ||
                              _picked == null ||
                              _reason.text.trim().isEmpty
                          ? null
                          : _save,
                      child: Text(l10n.integritySave),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

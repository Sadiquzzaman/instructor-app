import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/tests/data/tests.dart';

/// A student's result (the web's StudentExamResults): score, percentage,
/// grade, how many right and wrong, then every question with their answer,
/// the right one and the marks.
class TestResultScreen extends ConsumerWidget {
  const TestResultScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    String n(num v) => OrgTime.number(v, language);
    final result = ref.watch(testResultProvider(id));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: result.when(
          loading: () => LoadingView(semanticsLabel: l10n.testsResultsTitle),
          // 403 "Result has not been published yet" (no code yet, tes-taker issue).
          error: (e, _) => e is ApiException && e.statusCode == 403
              ? EmptyView(
                  icon: Icons.hourglass_empty,
                  title: l10n.testsResultsTitle,
                  message: l10n.appResultNotPublished,
                )
              : ErrorView(
                  title: l10n.testsResultsFailed,
                  retryLabel: l10n.uiErrorRetry,
                  onRetry: () => ref.invalidate(testResultProvider(id)),
                ),
          data: (r) => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(l10n.testsResultsTitle, style: text.headlineSmall),
              Text(
                [
                  r.subject ?? l10n.testsResultsFallbackSubject,
                  if (r.submittedAt != null)
                    l10n.testsResultsSubmitted(
                      OrgTime.dateTime(r.submittedAt!, language),
                    ),
                ].join(' · '),
                style: text.bodyMedium?.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _Stat(
                    l10n.testsResultsScore,
                    r.totalScore == null
                        ? '—'
                        : r.maxScore == null
                        ? n(r.totalScore!)
                        : '${n(r.totalScore!)}/${n(r.maxScore!)}',
                  ),
                  _Stat(
                    l10n.testsResultsPercentage,
                    r.percentage == null
                        ? '—'
                        : '${n(num.parse(r.percentage!.toStringAsFixed(1)))}%',
                  ),
                  if (r.grade != null) _Stat(l10n.testsResultsGrade, r.grade!),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.appResultSummary(r.correct, r.wrong, r.unanswered),
                style: text.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(l10n.testsResultsAnswerSheet, style: text.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              for (final (i, q) in r.questions.indexed) ...[
                if (q.passage != null &&
                    (i == 0 || r.questions[i - 1].passage != q.passage))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: colors.canvas,
                        borderRadius: AppRadius.inputAll,
                      ),
                      child: SelectableText(q.passage!, style: text.bodyMedium),
                    ),
                  ),
                _QuestionCard(number: i + 1, q: q),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 104),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: AppRadius.inputAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodySmall?.copyWith(color: colors.inkMuted)),
          Text(value, style: text.titleLarge),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.number, required this.q});

  final int number;
  final ResultQuestion q;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final verdict = q.studentAnswer.isEmpty
        ? (l10n.appResultNoAnswer, StatusTone.neutral)
        : q.isCorrect == true
        ? (l10n.appResultCorrect, StatusTone.success)
        : q.isCorrect == false
        ? (l10n.appResultIncorrect, StatusTone.danger)
        : null;
    return AppCard(
      key: Key('result-q$number'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.appResultQuestion(number),
                  style: text.labelMedium?.copyWith(color: colors.inkMuted),
                ),
              ),
              if (verdict != null)
                StatusPill(label: verdict.$1, tone: verdict.$2),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(
            q.question,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.appResultYourAnswer,
            style: text.labelSmall?.copyWith(color: colors.inkMuted),
          ),
          Text(
            q.studentAnswer.isEmpty
                ? l10n.appResultNoAnswer
                : q.studentAnswer.join('\n'),
            style: text.bodyMedium,
          ),
          if (q.correctAnswer.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.appResultCorrectAnswer,
              style: text.labelSmall?.copyWith(color: colors.inkMuted),
            ),
            Text(
              q.correctAnswer.join('\n'),
              style: text.bodyMedium?.copyWith(color: colors.success),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.appResultMarks(q.marks, q.points),
            style: text.bodySmall?.copyWith(color: colors.inkMuted),
          ),
        ],
      ),
    );
  }
}

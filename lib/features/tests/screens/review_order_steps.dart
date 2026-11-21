import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/features/tests/data/test_draft.dart';
import 'package:instructor_app/features/tests/screens/question_editor.dart';

/// The first line of a question's or passage's plain text.
String _firstLine(String text) => text.trim().split('\n').first.trim();

/// The web's Review step: the test's summary, then every question as
/// students will read it, subject by subject.
class ReviewStep extends StatelessWidget {
  const ReviewStep({required this.draft, super.key});

  final TestDraft draft;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final d = draft;
    final passing = num.tryParse(d.passingScore.trim());
    final negative = num.tryParse(d.negativePercent.trim());
    final facts = [
      (l10n.createTestReviewName, d.name.trim().isEmpty ? '—' : d.name.trim()),
      (
        l10n.createTestReviewSubjects,
        d.subjects.isEmpty ? '—' : d.subjects.map((s) => s.name).join(', '),
      ),
      (
        l10n.createTestReviewDuration,
        l10n.createTestReviewMinutes(num.tryParse(d.duration.trim()) ?? 0),
      ),
      (l10n.createTestReviewQuestions, '${d.questionCount}'),
      (l10n.createTestReviewMarks, '${d.totalMarks}'),
      (
        l10n.createTestReviewPassing,
        passing == null ? l10n.createTestReviewNone : '$passing',
      ),
      (
        l10n.createTestReviewNegative,
        d.negative && negative != null
            ? '$negative%'
            : l10n.createTestReviewNone,
      ),
    ];
    // Numbered in order across subjects and passages, as on the web.
    var n = 0;
    Widget preview(DraftQuestion q) {
      n++;
      return Padding(
        key: Key('review-question-${q.id}'),
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.createTestReviewQuestionMeta(
                n,
                typeName(l10n, q.subType, type: q.type),
                q.points,
              ),
              style: muted,
            ),
            if (q.instruction.trim().isNotEmpty)
              Text(q.instruction.trim(), style: text.bodySmall),
            Text(q.text.trim(), style: text.bodyMedium),
            if (q.subType != 'matching-ordering' && q.options.isNotEmpty)
              for (final (i, o) in q.options.indexed)
                Text(
                  '${String.fromCharCode(65 + i)}. ${o.text}',
                  style: text.bodySmall,
                ),
            if (q.subType == 'matching-ordering')
              for (var i = 0; i < q.left.length && i < q.right.length; i++)
                Text(
                  '${q.left[i].text} → ${q.right[i].text}',
                  style: text.bodySmall,
                ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.createTestReviewSummary, style: text.titleSmall),
              for (final (label, value) in facts)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(label, style: muted)),
                      Expanded(
                        child: Text(
                          value,
                          style: text.bodyMedium,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.createTestReviewPreview, style: text.titleSmall),
              if (d.questions.isEmpty)
                Text(l10n.createTestReviewEmpty, style: muted)
              else
                for (final s in d.subjects)
                  if (s.questions.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(s.name, style: text.titleSmall),
                    for (final q in s.questions)
                      if (q.isPassage) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(l10n.createTestReviewPassage, style: muted),
                        Text(q.text.trim(), style: text.bodyMedium),
                        for (final c in q.children) preview(c),
                      ] else
                        preview(q),
                  ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The web's Order step: one order across subjects. Each row moves up or
/// down; on a tablet it can also be dragged.
class OrderStep extends StatelessWidget {
  const OrderStep({required this.draft, required this.onChanged, super.key});

  final TestDraft draft;
  final ValueChanged<TestDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final rows = draft.ordered;
    final ids = [for (final (_, q) in rows) q.id];
    void move(int from, int to) {
      final next = [...ids];
      next.insert(to, next.removeAt(from));
      onChanged(draft.copyWith(order: next));
    }

    final drag =
        MediaQuery.sizeOf(context).width >= AppSpacing.tabletBreakpoint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.createTestReorderTitle, style: text.titleMedium),
        Text(
          l10n.createTestReorderIntro,
          style: text.bodySmall?.copyWith(color: colors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: move,
          children: [
            for (final (i, (s, q)) in rows.indexed)
              Padding(
                key: ValueKey('order-${q.id}'),
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: AppCard(
                  child: Row(
                    children: [
                      if (drag)
                        ReorderableDragStartListener(
                          index: i,
                          child: Tooltip(
                            message: l10n.createTestReorderDrag,
                            child: const Padding(
                              padding: EdgeInsets.all(AppSpacing.xs),
                              child: Icon(Icons.drag_indicator),
                            ),
                          ),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: AppSpacing.sm,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  l10n.createTestReorderQuestionNumber(i + 1),
                                  style: text.labelLarge?.copyWith(
                                    color: colors.primary,
                                  ),
                                ),
                                Chip(
                                  label: Text(s.name),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                            Text(
                              _firstLine(q.text).isNotEmpty
                                  ? _firstLine(q.text)
                                  : q.isPassage
                                  ? l10n.createTestReorderPassageQuestion
                                  : l10n.createTestReorderUntitled,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: Key('order-up-$i'),
                        tooltip: l10n.createTestReorderMoveUp(i + 1),
                        icon: const Icon(Icons.arrow_upward),
                        onPressed: i == 0 ? null : () => move(i, i - 1),
                      ),
                      IconButton(
                        key: Key('order-down-$i'),
                        tooltip: l10n.createTestReorderMoveDown(i + 1),
                        icon: const Icon(Icons.arrow_downward),
                        onPressed: i == rows.length - 1
                            ? null
                            : () => move(i, i + 1),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

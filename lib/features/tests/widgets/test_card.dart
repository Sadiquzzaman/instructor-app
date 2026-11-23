import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/tests/data/tests.dart';

String testStatusName(AppLocalizations l10n, String s) => switch (s) {
  'ongoing' => l10n.testsStatusOngoing,
  'completed' => l10n.testsStatusCompleted,
  _ => l10n.testsStatusPending,
};

StatusTone testStatusTone(String s) => switch (s) {
  'ongoing' => StatusTone.primary,
  'completed' => StatusTone.success,
  _ => StatusTone.warning,
};

/// A test in a list (the web's TestCard for a student): its name, type,
/// status, subject, schedule and how many have handed in; Results once it
/// is over. Starting a test comes with the next PR.
class TestCard extends StatelessWidget {
  const TestCard({required this.test, this.onStart, this.onOpen, super.key});

  final TestItem test;

  /// Opens the test's page (teachers); null: the card is not tappable.
  final VoidCallback? onOpen;

  /// Opens the test; null hides Start.
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final t = test;
    final progress = t.participants > 0 ? t.submitted / t.participants : 0.0;
    return AppCard(
      key: Key('test-${t.id}'),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(t.name, style: text.titleSmall)),
              const SizedBox(width: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  StatusPill(
                    label: t.ielts
                        ? l10n.testsCategoryIelts
                        : l10n.testsCategoryAcademic,
                    tone: StatusTone.primary,
                  ),
                  StatusPill(
                    label: testStatusName(l10n, t.status),
                    tone: testStatusTone(t.status),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xs,
            children: [
              for (final (label, value) in [
                (
                  t.ielts ? l10n.testsCardModules : l10n.testsCardSubject,
                  t.subject ?? '—',
                ),
                (
                  l10n.testsCardParticipants,
                  OrgTime.number(t.participants, language),
                ),
                (
                  l10n.testsCardSubmitted,
                  OrgTime.number(t.submitted, language),
                ),
              ])
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: text.labelSmall?.copyWith(color: colors.inkMuted),
                    ),
                    Text(
                      value,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            label: l10n.testsCardProgress,
            value: l10n.testsCardProgressValue(t.submitted, t.participants),
            child: LinearProgressIndicator(value: progress),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            t.startsAt != null && t.endsAt != null
                ? '${OrgTime.dateTime(t.startsAt!, language)} – ${OrgTime.dateTime(t.endsAt!, language)}'
                : l10n.testsCardNoSchedule,
            style: text.bodySmall,
          ),
          if (t.status == 'completed' ||
              (t.status == 'ongoing' && onStart != null)) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: t.status == 'completed'
                  ? AppButton(
                      label: l10n.testsCardResults,
                      variant: AppButtonVariant.secondary,
                      onPressed: () =>
                          context.push('${AppRoutes.tests}/${t.id}/results'),
                    )
                  : AppButton(
                      label: l10n.testsCardStart,
                      icon: Icons.play_arrow,
                      onPressed: onStart,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';

enum StatusTone { neutral, primary, success, warning, danger, info }

/// A small rounded status label. Show statuses with a translated [label],
/// never the raw API value (design system §P1-05 "Status").
class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    this.tone = StatusTone.neutral,
    super.key,
  });

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final (foreground, background) = switch (tone) {
      StatusTone.neutral => (c.inkMuted, c.canvas),
      StatusTone.primary => (c.primary, c.primarySoft),
      StatusTone.success => (c.success, c.successSoft),
      StatusTone.warning => (c.warning, c.warningSoft),
      StatusTone.danger => (c.danger, c.dangerSoft),
      StatusTone.info => (c.info, c.infoSoft),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.pill,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs / 2,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: foreground),
        ),
      ),
    );
  }
}

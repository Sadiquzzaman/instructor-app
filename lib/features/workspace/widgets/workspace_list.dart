import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/workspace/data/workspace_repository.dart';

/// The person's workspaces as cards (the web's WorkspaceSwitcher and
/// StudentWorkspaceCards): name, role, "Pending approval", a tick on the
/// current one. Tapping one switches to it; [onSwitched] runs afterwards.
class WorkspaceList extends ConsumerStatefulWidget {
  const WorkspaceList({required this.contexts, this.onSwitched, super.key});

  final List<WorkspaceContext> contexts;
  final VoidCallback? onSwitched;

  @override
  ConsumerState<WorkspaceList> createState() => _WorkspaceListState();
}

class _WorkspaceListState extends ConsumerState<WorkspaceList> {
  String? _switching;
  String? _error;

  Future<void> _select(WorkspaceContext context) async {
    if (_switching != null) return;
    setState(() {
      _switching = context.key;
      _error = null;
    });
    try {
      await switchWorkspace(ref, context);
      widget.onSwitched?.call();
    } on Object catch (e) {
      if (mounted) setState(() => _error = apiErrorText(this.context.l10n, e));
    } finally {
      if (mounted) setState(() => _switching = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);
    final usable = widget.contexts.where((c) => c.actionable).toList();
    if (usable.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Text(l10n.dashboardStudentEmpty, style: text.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              ref.levels(context, l10n.dashboardStudentEmptyDetail),
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: colors.inkMuted),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              _error!,
              style: text.bodyMedium?.copyWith(color: colors.danger),
            ),
          ),
        for (final c in usable) ...[
          AppCard(
            key: Key('workspace-${c.key}'),
            onTap: () => _select(c),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // The API's name for it; "My Teaching" for one's own.
                        c.type == 'personal_teacher' && c.label.isEmpty
                            ? l10n.shellWorkspaceMyTeaching
                            : c.label,
                        style: text.titleMedium,
                      ),
                      if (c.roleLabel != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          c.roleLabel!,
                          style: text.bodySmall?.copyWith(
                            color: colors.inkMuted,
                          ),
                        ),
                      ],
                      if (c.isPending) ...[
                        const SizedBox(height: AppSpacing.sm),
                        StatusPill(
                          label: l10n.dashboardStudentPendingApproval,
                          tone: StatusTone.warning,
                        ),
                      ],
                    ],
                  ),
                ),
                if (_switching == c.key)
                  const SizedBox.square(
                    dimension: AppSpacing.xl,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (c.isCurrent(session))
                  Icon(Icons.check_circle, color: colors.primary)
                else
                  Icon(Icons.chevron_right, color: colors.inkMuted),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

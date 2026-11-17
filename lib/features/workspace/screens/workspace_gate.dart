import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/workspace/data/workspace_repository.dart';
import 'package:instructor_app/features/workspace/widgets/workspace_list.dart';

/// Shows the workspace picker instead of [child] when the person signed in
/// with several workspaces and none chosen yet; otherwise [child].
class WorkspaceGate extends ConsumerWidget {
  const WorkspaceGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ref
        .watch(needsWorkspaceChoiceProvider)
        .when(
          data: (needed) => needed ? const WorkspacePickerScreen() : child,
          loading: () =>
              Scaffold(body: LoadingView(semanticsLabel: l10n.uiLoading)),
          error: (e, _) => Scaffold(
            body: ErrorView(
              title: l10n.uiErrorTitle,
              retryLabel: l10n.uiErrorRetry,
              onRetry: () => ref.invalidate(workspaceContextsProvider),
            ),
          ),
        );
  }
}

/// "Your workspaces": choose where to work (the web's student workspace
/// cards and /select-context).
class WorkspacePickerScreen extends ConsumerWidget {
  const WorkspacePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final contexts = ref.watch(workspaceContextsProvider).value ?? const [];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.dashboardStudentTitle,
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    ref.levels(context, l10n.dashboardStudentIntro),
                    style: text.bodyLarge?.copyWith(color: colors.inkMuted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  WorkspaceList(contexts: contexts),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The switcher's sheet: "Workspaces" and the list.
Future<void> showWorkspaceSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final contexts =
              ref.watch(workspaceContextsProvider).value ?? const [];
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l10n.shellWorkspaceTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  WorkspaceList(
                    contexts: contexts,
                    onSwitched: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

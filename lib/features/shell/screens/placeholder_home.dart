import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/config/app_config.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/language_switcher.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/features/auth/data/auth_repository.dart';
import 'package:instructor_app/features/workspace/data/workspace_repository.dart';
import 'package:instructor_app/features/workspace/screens/workspace_gate.dart';

/// Stands in for the app shell until the menu exists (Stage 0, PR 10): the
/// brand name (not translated), who is signed in, the workspace switcher, the
/// language switch and sign-out.
class PlaceholderHome extends ConsumerWidget {
  const PlaceholderHome({super.key});

  /// The current workspace's name, as the web's switcher shows it.
  static String workspaceLabel(
    AppLocalizations l10n,
    Session session,
    List<WorkspaceContext> contexts,
  ) {
    for (final c in contexts) {
      if (c.isCurrent(session) && c.label.isNotEmpty) return c.label;
    }
    return switch (session.contextType) {
      'organization' => session.organizationName ?? l10n.shellOrganization,
      'personal_teacher' => l10n.shellWorkspaceMyTeaching,
      'individual_teacher' => l10n.shellWorkspaceFallback,
      _ => l10n.shellWorkspaceFallback,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);
    final contexts = ref.watch(workspaceContextsProvider).value ?? const [];
    final canSwitch = contexts.where((c) => c.actionable).length > 1;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppConfig.appName,
                  style: text.headlineMedium?.copyWith(color: colors.primary),
                ),
                if (session != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  // The person's name, as the API sent it: not translated.
                  if (session.fullName != null)
                    Text(
                      session.fullName!,
                      style: text.bodyLarge?.copyWith(color: colors.inkMuted),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    key: const Key('workspace-switcher'),
                    label: workspaceLabel(l10n, session, contexts),
                    icon: canSwitch ? Icons.swap_horiz : Icons.business,
                    variant: AppButtonVariant.secondary,
                    onPressed: canSwitch
                        ? () => showWorkspaceSheet(context)
                        : null,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                const LanguageSwitcher(),
                if (session != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: l10n.shellSignOut,
                    icon: Icons.logout,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => signOut(ref),
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

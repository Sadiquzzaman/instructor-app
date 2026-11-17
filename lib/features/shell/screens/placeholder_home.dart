import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/config/app_config.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/language_switcher.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/features/auth/data/auth_repository.dart';

/// Stands in for the app shell until the menu exists (Stage 0, PR 10): the
/// brand name (not translated), who is signed in, the language switch and
/// sign-out.
class PlaceholderHome extends ConsumerWidget {
  const PlaceholderHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final session = ref.watch(sessionHolderProvider).current;
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
                  // What the person typed or the API sent: not translated.
                  Text(
                    [
                      session.fullName,
                      session.organizationName,
                    ].whereType<String>().join(' · '),
                    style: text.bodyLarge?.copyWith(color: colors.inkMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                const LanguageSwitcher(),
                if (session != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: context.l10n.shellSignOut,
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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/config/app_config.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';

/// Home until Today exists (stage 1): the brand and who is signed in. The
/// menu, the workspace switcher, the language switch and Sign out are in the
/// shell around it.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppConfig.appName,
              style: text.headlineMedium?.copyWith(color: colors.primary),
            ),
            // The person's name as the API sent it: not translated.
            if (session?.fullName != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                session!.fullName!,
                style: text.bodyLarge?.copyWith(color: colors.inkMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

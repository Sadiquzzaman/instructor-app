import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/config/app_config.dart';
import 'package:instructor_app/core/l10n/language_switcher.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';

/// Stands in for the app shell until sign-in and the menu exist (Stage 0,
/// PRs 7 and 10): the brand name (not translated) and the language switch.
class PlaceholderHome extends StatelessWidget {
  const PlaceholderHome({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppConfig.appName,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(color: colors.primary),
              ),
              const SizedBox(height: AppSpacing.lg),
              const LanguageSwitcher(),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/config/app_config.dart';
import 'package:instructor_app/core/l10n/language_switcher.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';

/// The frame of every signed-out screen (the web's AuthLayout + AuthHeading):
/// back button when there is somewhere to go back to, the language switch,
/// the brand, a title with an optional intro, then the content. Centred and
/// at most 420 px wide, so it works from 360 px phones to tablets.
class AuthPage extends StatelessWidget {
  const AuthPage({
    required this.title,
    required this.children,
    this.intro,
    super.key,
  });

  final String title;
  final Widget? intro;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: context.canPop() ? const BackButton() : null,
        actions: const [
          LanguageSwitcher(),
          SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppConfig.appName,
                    textAlign: TextAlign.center,
                    style: text.headlineMedium?.copyWith(color: colors.primary),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    title,
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  if (intro != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    DefaultTextStyle.merge(
                      textAlign: TextAlign.center,
                      style: text.bodyLarge?.copyWith(color: colors.inkMuted),
                      child: intro!,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A coloured message box above a form: an error or a success.
class NoticeBox extends StatelessWidget {
  const NoticeBox({required this.message, this.success = false, super.key});

  final String message;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final (fg, bg, icon) = success
        ? (c.success, c.successSoft, Icons.check_circle_outline)
        : (c.danger, c.dangerSoft, Icons.error_outline);
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: bg, borderRadius: AppRadius.inputAll),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: fg),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Don't have an account? Sign Up" and similar.
class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({
    required this.text,
    required this.label,
    required this.onTap,
    super.key,
  });

  final String text;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(text, style: Theme.of(context).textTheme.bodyMedium),
        TextButton(onPressed: onTap, child: Text(label)),
      ],
    );
  }
}

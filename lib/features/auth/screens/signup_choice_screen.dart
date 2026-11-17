import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/features/auth/widgets/auth_page.dart';

/// Sign-up starts with the kind of account (the web's SignUpChoice).
class SignUpChoiceScreen extends StatelessWidget {
  const SignUpChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthPage(
      title: l10n.authSignupTitle,
      intro: Text(l10n.authSignupChoose),
      children: [
        _Choice(
          title: l10n.authSignupStudent,
          detail: l10n.authSignupStudentDescription,
          onTap: () => context.push(AppRoutes.signUpStudent),
        ),
        const SizedBox(height: AppSpacing.md),
        _Choice(
          title: l10n.authSignupTeacher,
          detail: l10n.authSignupTeacherDescription,
          onTap: () => context.push(AppRoutes.signUpTeacher),
        ),
        const SizedBox(height: AppSpacing.md),
        _Choice(
          title: l10n.authSignupOrganization,
          detail: l10n.authSignupOrganizationDescription,
          onTap: () => context.push(AppRoutes.signUpOrganization),
        ),
        const SizedBox(height: AppSpacing.lg),
        AuthFooterLink(
          text: l10n.authHaveAccount,
          label: l10n.authLogIn,
          onTap: () => context.go(AppRoutes.login),
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    detail,
                    style: text.bodyMedium?.copyWith(color: colors.inkMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colors.inkMuted),
          ],
        ),
      ),
    );
  }
}

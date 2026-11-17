import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_button.dart';

/// Owners and admins (and a solo teacher in their own workspace) see the
/// "upgrade" wording for a locked feature; everyone else "ask your admin"
/// (design §8.3, the web's useBillingAccess).
bool canManagePlan(Session? s) {
  if (s == null) return false;
  if (s.contextType == 'personal_teacher') return true;
  return s.isOrganization &&
      (s.memberRole == 'OWNER' || s.memberRole == 'ADMIN');
}

/// Handles the codes every screen can meet (API guide §4, the IELTS and
/// branch-manager answers): a locked feature or a plan limit opens the
/// locked-feature sheet; NOT_FOR_BRANCH_MANAGERS and NOT_IN_IELTS show a short
/// message. Returns false for anything else, which the screen handles.
Future<bool> handleCommonApiError(
  BuildContext context,
  Object error, {
  required Session? session,
}) async {
  if (error is! ApiException) return false;
  final l10n = context.l10n;
  switch (error.code) {
    case 'FEATURE_NOT_IN_PLAN' || 'PLAN_LIMIT_REACHED':
      await showLockedFeature(
        context,
        limit: error.isPlanLimit,
        canManage: canManagePlan(session),
      );
      return true;
    case 'NOT_FOR_BRANCH_MANAGERS':
      _snack(context, l10n.appNotForBranchManagers);
      return true;
    case 'NOT_IN_IELTS':
      _snack(context, l10n.appNotInWorkspace);
      return true;
  }
  return false;
}

void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

/// "Not in your plan" / "Plan limit reached" with the web's wording by role.
/// No upgrade button and no link to buy elsewhere (CLAUDE.md "Payments").
Future<void> showLockedFeature(
  BuildContext context, {
  required bool limit,
  required bool canManage,
}) => showModalBottomSheet<void>(
  context: context,
  builder: (sheetContext) {
    final l10n = sheetContext.l10n;
    final text = Theme.of(sheetContext).textTheme;
    return SafeArea(
      // Scrolls on a short screen or with large text.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.lock_outline, size: AppSpacing.xxl),
            const SizedBox(height: AppSpacing.md),
            Text(
              limit ? l10n.featuresLockedLimitTitle : l10n.featuresLockedTitle,
              style: text.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              canManage
                  ? l10n.featuresLockedOwnerMessage
                  : l10n.featuresLockedMemberMessage,
              style: text.bodyLarge,
              textAlign: TextAlign.center,
            ),
            // The plan's features and "Request this feature", in the app.
            if (canManage) ...[
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  context.go(AppRoutes.features);
                },
                child: Text(l10n.featuresLockedMoreFeatures),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: l10n.featuresLockedClose,
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        ),
      ),
    );
  },
);

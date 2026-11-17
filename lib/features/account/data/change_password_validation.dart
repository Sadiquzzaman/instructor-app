import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/features/auth/data/signup_validation.dart';

/// The web's validateChangePassword (frontend/utils/auth/validation.ts), one
/// problem at a time in its order: current, new (strength, not the same),
/// confirmation.
Map<String, String> validateChangePassword({
  required String current,
  required String next,
  required String confirm,
  required AppLocalizations l10n,
}) {
  final complexity = SignUpValidation.passwordComplexity(
    next,
    l10n,
    field: 'newPassword',
  );
  if (current.isEmpty) {
    return {'current': l10n.validationCurrentPasswordRequired};
  }
  if (complexity != null) return {'new': complexity};
  if (next == current) return {'new': l10n.validationNewPasswordSame};
  if (confirm.isEmpty) {
    return {'confirm': l10n.validationConfirmNewPasswordRequired};
  }
  if (next != confirm) return {'confirm': l10n.validationNewPasswordMismatch};
  return const {};
}

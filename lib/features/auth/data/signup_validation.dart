import 'package:instructor_app/core/l10n/l10n.dart';

/// The web's sign-up and reset checks (frontend/utils/auth/validation.ts),
/// with its wording. Each returns field → message for the first problem only,
/// in the web's order, so one error shows at a time.
abstract final class SignUpValidation {
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final _bdPhone = RegExp(r'^01\d{9}$');

  /// getPasswordComplexityError: length, upper, lower, number, special.
  /// [field] is `password` or `newPassword` (changes the wording).
  static String? passwordComplexity(
    String password,
    AppLocalizations l10n, {
    String field = 'password',
  }) {
    if (password.isEmpty) return l10n.validationPasswordRequired(field);
    if (password.length < 8) return l10n.validationPasswordShort(field);
    if (!RegExp('[A-Z]').hasMatch(password)) {
      return l10n.validationPasswordUppercase(field);
    }
    if (!RegExp('[a-z]').hasMatch(password)) {
      return l10n.validationPasswordLowercase(field);
    }
    if (!RegExp('[0-9]').hasMatch(password)) {
      return l10n.validationPasswordNumber(field);
    }
    if (!RegExp('[^A-Za-z0-9]').hasMatch(password)) {
      return l10n.validationPasswordSpecial(field);
    }
    return null;
  }

  /// validateSignUpForm and validateOrganizationSignUpForm (when
  /// [organizationName] is given).
  static Map<String, String> signUp(
    SignUpForm f,
    AppLocalizations l10n, {
    String? organizationName,
  }) {
    final phone = f.phone.trim();
    final email = f.email.trim();
    final complexity = passwordComplexity(f.password, l10n);
    if (organizationName != null && organizationName.trim().isEmpty) {
      return {'organization_name': l10n.validationOrganizationNameRequired};
    }
    if (f.fullName.trim().isEmpty) {
      return {'full_name': l10n.validationFullNameRequired};
    }
    if (phone.isEmpty) return {'phone': l10n.validationPhoneRequired};
    if (phone.length != 11 || !_bdPhone.hasMatch(phone)) {
      return {'phone': l10n.validationPhoneInvalid};
    }
    if (email.isEmpty) return {'email': l10n.validationEmailRequired};
    if (!_email.hasMatch(email)) return {'email': l10n.validationEmailInvalid};
    if (complexity != null) return {'password': complexity};
    if (f.confirmPassword.isEmpty) {
      return {'confirm_password': l10n.validationConfirmPasswordRequired};
    }
    if (f.password != f.confirmPassword) {
      return {'confirm_password': l10n.validationPasswordMismatch};
    }
    if (!f.agreed) return {'terms': l10n.validationTermsRequired};
    return const {};
  }

  /// validateResetPassword.
  static Map<String, String> reset(
    String password,
    String confirm,
    AppLocalizations l10n,
  ) {
    final complexity = passwordComplexity(password, l10n);
    if (complexity != null) return {'password': complexity};
    if (confirm.isEmpty) {
      return {'confirm_password': l10n.validationConfirmPasswordRequired};
    }
    if (password != confirm) {
      return {'confirm_password': l10n.validationPasswordMismatch};
    }
    return const {};
  }

  /// The web's maskInputValue: first and last three characters kept.
  static String mask(String value) {
    if (value.length <= 6) return value;
    return '${value.substring(0, 3)}${'*' * (value.length - 6)}'
        '${value.substring(value.length - 3)}';
  }
}

/// What a sign-up form holds.
class SignUpForm {
  const SignUpForm({
    required this.fullName,
    required this.phone,
    required this.email,
    required this.password,
    required this.confirmPassword,
    required this.agreed,
  });

  final String fullName;
  final String phone;
  final String email;
  final String password;
  final String confirmPassword;
  final bool agreed;
}

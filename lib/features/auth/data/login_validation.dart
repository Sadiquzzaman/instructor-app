import 'package:instructor_app/core/l10n/l10n.dart';

/// The web's sign-in checks (frontend/utils/auth/validation.ts:
/// validateForgotIdentifier, validateLoginForm), with the web's wording.
abstract final class LoginValidation {
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final _bdPhone = RegExp(r'^01\d{9}$');
  static final _digits = RegExp(r'^\d+$');

  /// An email or a Bangladeshi mobile number (01XXXXXXXXX); null when valid.
  static String? identifier(String raw, AppLocalizations l10n) {
    final value = raw.trim();
    final isEmail = value.contains('@');
    final isPhone = _digits.hasMatch(value);
    if (value.isEmpty) return l10n.validationIdentifierRequired;
    if (isPhone && value.length != 11) return l10n.validationPhoneLength;
    if (isPhone && !_bdPhone.hasMatch(value)) {
      return l10n.validationPhoneInvalidBd;
    }
    if (isEmail && !_email.hasMatch(value)) {
      return l10n.validationEmailInvalidShort;
    }
    if (!isEmail && !isPhone) return l10n.validationIdentifierInvalid;
    return null;
  }

  /// Required and at least 8 characters; null when valid.
  static String? password(String value, AppLocalizations l10n) {
    if (value.isEmpty) return l10n.validationPasswordRequired('password');
    if (value.length < 8) return l10n.validationPasswordShort('password');
    return null;
  }

  /// The body field for the identifier: `email` (lower-cased) or `phone`.
  static Map<String, String> identifierField(String raw) {
    final value = raw.trim();
    return value.contains('@')
        ? {'email': value.toLowerCase()}
        : {'phone': value};
  }
}

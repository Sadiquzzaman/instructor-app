import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/l10n/l10n.dart';

/// The app's sentence for an error code of sign-up, verification, password
/// reset or sign-in (tes-taker#345). The server's `message` stays English for
/// its logs; the app says it in the person's language. Null when the error
/// has no such code, so the screen falls back to its general message.
String? authErrorText(ApiException e, AppLocalizations l10n) =>
    switch (e.code) {
      'PHONE_ALREADY_REGISTERED' => l10n.appPhoneTaken,
      'EMAIL_ALREADY_REGISTERED' => l10n.appEmailTaken,
      'OTP_SEND_FAILED' => l10n.appCodeNotSent,
      'ACCOUNT_NOT_FOUND' => l10n.appAccountNotFound,
      'PHONE_ALREADY_VERIFIED' => l10n.appAlreadyVerified,
      'OTP_INVALID' => l10n.appCodeWrong,
      'OTP_EXPIRED' => l10n.appCodeExpired,
      'OTP_LOCKED' => l10n.appCodeLocked,
      'INVALID_CREDENTIALS' => l10n.appLoginInvalid,
      'ACCOUNT_NOT_VERIFIED' => l10n.appLoginNotVerified,
      'ACCOUNT_DISABLED' => l10n.appLoginDisabled,
      _ => null,
    };

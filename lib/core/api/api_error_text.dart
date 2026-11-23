import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/l10n/l10n.dart';

/// A short sentence for an error the screen has no special handling for.
/// Screens that care about a [ApiException.code] (locked features, plan
/// limits, NOT_IN_IELTS, …) check it themselves first.
String apiErrorText(AppLocalizations l10n, Object error) {
  if (error is ApiException &&
      (error.kind == ApiErrorKind.network ||
          error.kind == ApiErrorKind.timeout)) {
    return l10n.appNoConnection;
  }
  return l10n.uiErrorTitle;
}

import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/l10n/generated/app_localizations.dart';

export 'package:instructor_app/l10n/generated/app_localizations.dart';

/// The app's two languages (FND-18).
abstract final class AppLanguages {
  static const english = Locale('en');
  static const bangla = Locale('bn');
  static const supported = [english, bangla];

  static bool isBangla(Locale locale) => locale.languageCode == 'bn';

  /// `en` / `bn` from any locale or code; anything else is English.
  static Locale from(String? code) => code == 'bn' ? bangla : english;

  /// The app's messages plus Flutter's own texts (dialogs, pickers, tooltips,
  /// the iOS text-selection menu). Since Flutter 3.47 the Material and
  /// Cupertino ones live in `material_ui` and `cupertino_ui`, which the app's
  /// widgets read; gen-l10n's `AppLocalizations.localizationsDelegates` would
  /// add the older, deprecated ones from the SDK instead.
  static const List<LocalizationsDelegate<Object?>> delegates = [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
}

extension L10nContext on BuildContext {
  /// This screen's messages: `context.l10n.uiErrorRetry`.
  AppLocalizations get l10n => AppLocalizations.of(this);
}

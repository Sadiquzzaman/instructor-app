import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:instructor_app/core/l10n/l10n.dart';

/// Set in main() with the loaded instance (overridden in tests).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override sharedPreferencesProvider'),
);

/// The language the app shows.
///
/// Until sign-in exists: the choice saved on this phone, else the phone's own
/// language when it is Bangla, else English. With sign-in (Stage 0 PR 7) the
/// account's language and then the organisation's come first (STAGE-0-PLAN §7).
final languageProvider = NotifierProvider<LanguageController, Locale>(
  LanguageController.new,
);

class LanguageController extends Notifier<Locale> {
  static const prefsKey = 'language';

  @override
  Locale build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(prefsKey);
    if (saved != null) return AppLanguages.from(saved);
    return AppLanguages.from(PlatformDispatcher.instance.locale.languageCode);
  }

  /// Switches the language and remembers it on this phone.
  Future<void> choose(Locale locale) async {
    final language = AppLanguages.from(locale.languageCode);
    state = language;
    await ref
        .read(sharedPreferencesProvider)
        .setString(prefsKey, language.languageCode);
  }

  /// English ↔ Bangla.
  Future<void> toggle() => choose(
    AppLanguages.isBangla(state) ? AppLanguages.english : AppLanguages.bangla,
  );
}

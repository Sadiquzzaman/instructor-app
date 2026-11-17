import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/language_controller.dart';
import 'package:instructor_app/core/l10n/l10n.dart';

/// The web's language switch: shows the other language's name ("বাংলা" /
/// "English") and switches to it. When signed in, the choice is also saved
/// on the account (`PATCH /user/me/locale`), as on the web; if that fails the
/// phone keeps the new language and says it was not saved to the account.
class LanguageSwitcher extends ConsumerWidget {
  const LanguageSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: l10n.languageSwitchToLabel,
      excludeSemantics: true,
      child: TextButton.icon(
        onPressed: () async {
          final messenger = ScaffoldMessenger.maybeOf(context);
          await ref.read(languageProvider.notifier).toggle();
          if (ref.read(sessionProvider) == null) return;
          final language = ref.read(languageProvider).languageCode;
          try {
            await ref
                .read(apiClientProvider)
                .patch('/user/me/locale', data: {'locale': language});
          } on ApiException {
            // In the new language: the app has already switched.
            final text = lookupAppLocalizations(AppLanguages.from(language))
                .languageSaveFailed;
            messenger?.showSnackBar(SnackBar(content: Text(text)));
          }
        },
        icon: const Icon(Icons.translate),
        label: Text(l10n.languageSwitchTo),
      ),
    );
  }
}

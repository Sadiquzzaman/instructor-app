import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/l10n/language_controller.dart';
import 'package:instructor_app/core/l10n/l10n.dart';

/// The web's language switch: shows the other language's name ("বাংলা" /
/// "English") and switches to it.
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
        onPressed: () => ref.read(languageProvider.notifier).toggle(),
        icon: const Icon(Icons.translate),
        label: Text(l10n.languageSwitchTo),
      ),
    );
  }
}

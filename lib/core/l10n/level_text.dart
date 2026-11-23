import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/l10n/level_labels.dart';

extension LevelText on WidgetRef {
  /// A message with its level tokens ([[Classes]], …) replaced by the
  /// workspace's words in the current language:
  /// `ref.levels(context.l10n.navClasses)`.
  String levels(BuildContext context, String message) =>
      watch(levelLabelsProvider)
          .apply(message, Localizations.localeOf(context).languageCode);
}

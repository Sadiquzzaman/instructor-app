import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/config/app_config.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/language_controller.dart';
import 'package:instructor_app/core/theme/app_theme.dart';
import 'package:instructor_app/features/shell/screens/placeholder_home.dart';

/// The root widget: the chosen language picks the messages and the theme
/// (Bangla fonts and line height). Routing comes with sign-in (PR 7).
class InstructorApp extends ConsumerWidget {
  const InstructorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      locale: language,
      supportedLocales: AppLanguages.supported,
      localizationsDelegates: AppLanguages.delegates,
      theme: AppTheme.light(bangla: AppLanguages.isBangla(language)),
      home: const PlaceholderHome(),
    );
  }
}

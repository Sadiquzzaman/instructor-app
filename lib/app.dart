import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/cache/read_cache.dart';
import 'package:instructor_app/core/config/app_config.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/language_controller.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/theme/app_theme.dart';
import 'package:instructor_app/features/version/screens/version_gate.dart';

/// The root widget: the chosen language picks the messages and the theme
/// (Bangla fonts and line height); the router picks the screen from the
/// session; the version check sits above everything (PM-03).
class InstructorApp extends ConsumerWidget {
  const InstructorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Saved answers go when the person signs out.
    ref.watch(readCacheJanitorProvider);
    final language = ref.watch(languageProvider);
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      locale: language,
      supportedLocales: AppLanguages.supported,
      localizationsDelegates: AppLanguages.delegates,
      theme: AppTheme.light(bangla: AppLanguages.isBangla(language)),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) =>
          VersionGate(child: child ?? const SizedBox.shrink()),
    );
  }
}

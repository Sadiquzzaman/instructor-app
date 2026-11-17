import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:instructor_app/app.dart';
import 'package:instructor_app/core/l10n/language_controller.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_theme.dart';

/// A ProviderContainer-backed app with saved preferences, as main() builds it.
Future<ProviderContainer> pumpInstructorApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final instance = await SharedPreferences.getInstance();
  await initializeDateFormatting();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(instance)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const InstructorApp(),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// One widget in the app's theme and a language, for widget tests.
Widget inLanguage(Widget child, {String language = 'en'}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: AppLanguages.supported,
  localizationsDelegates: AppLanguages.delegates,
  theme: AppTheme.light(bangla: language == 'bn'),
  home: Scaffold(body: Center(child: child)),
);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:instructor_app/app.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/language_controller.dart';
import 'package:instructor_app/core/theme/font_licenses.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  // Dates in English and Bangla (OrgTime).
  await initializeDateFormatting();
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  // The stored session before the first frame, so a signed-in person goes
  // straight home and never sees the login screen flash.
  await container.read(sessionHolderProvider).restore();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const InstructorApp(),
    ),
  );
}

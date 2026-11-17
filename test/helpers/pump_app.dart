import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:instructor_app/app.dart';
import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/device/device_info.dart';
import 'package:instructor_app/core/l10n/language_controller.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/links/open_link.dart';
import 'package:instructor_app/core/theme/app_theme.dart';

import 'fake_api.dart';

const testDevice = DeviceInfo(
  platform: 'ANDROID',
  name: 'Google Pixel 8',
  appVersion: '0.1.0',
);

/// The whole app as main() builds it, but against [api] (a fake server; by
/// default every build is up to date), an in-memory session and saved
/// preferences. Links that would open are added to [openedLinks].
Future<ProviderContainer> pumpInstructorApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  FakeApi? api,
  Session? session,
  List<Uri>? openedLinks,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final instance = await SharedPreferences.getInstance();
  await initializeDateFormatting();
  final fake = api ?? FakeApi();
  fake.routes.putIfAbsent(
    'GET /app/version',
    () =>
        (_) => ok({'update': 'NONE', 'minimum': '0.0.0', 'latest': '0.1.0'}),
  );
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(instance),
      sessionStoreProvider.overrideWithValue(MemorySessionStore(session)),
      deviceInfoProvider.overrideWithValue(Future.value(testDevice)),
      apiClientProvider.overrideWith((ref) {
        final sessions = ref.watch(sessionHolderProvider);
        return ApiClient(
          baseUrl: 'https://api.test/api/v1',
          sessions: sessions,
          device: () async => testDevice,
          onSessionExpired: sessions.clear,
          adapter: fake,
        );
      }),
      openLinkProvider.overrideWithValue((uri) async {
        openedLinks?.add(uri);
        return true;
      }),
    ],
  );
  addTearDown(container.dispose);
  // As main(): the stored session before the first frame.
  await container.read(sessionHolderProvider).restore();
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

/// Signs out the way a person does: open the menu (phone drawer), then
/// "Sign out".
Future<void> signOutFromMenu(WidgetTester tester) async {
  await tester.tap(find.byType(DrawerButton));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sign out'));
  await tester.pumpAndSettle();
}

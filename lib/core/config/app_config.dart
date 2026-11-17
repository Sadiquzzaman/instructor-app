/// Build-time settings, passed with `--dart-define`.
///
/// Beta is the default so a plain `flutter run` talks to the test server.
/// Production is added when it exists (STAGE-0-PLAN.md §9).
abstract final class AppConfig {
  /// The product name. A brand, so it is the same in Bangla and English.
  static const String appName = 'Instructor';

  /// The API's base URL, ending in `/api/v1`.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api-beta.instructor.academy/api/v1',
  );
}

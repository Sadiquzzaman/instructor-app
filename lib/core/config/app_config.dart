/// Build-time settings, passed with `--dart-define`.
///
/// Beta is the default, so a plain `flutter run` and every test build talk
/// to the test server. A store build passes `APP_ENV=production` once the
/// owner says production is live (docs/RELEASING.md); `API_BASE_URL` and
/// `WEB_BASE_URL` still override either one.
abstract final class AppConfig {
  /// The product name. A brand, so it is the same in Bangla and English.
  static const String appName = 'Instructor';

  /// `beta` (the default) or `production`.
  static const String environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'beta',
  );

  /// Whether this build talks to the live servers.
  static const bool isProduction = environment == 'production';

  static const String _betaApi = 'https://api-beta.instructor.academy/api/v1';
  static const String _betaWeb = 'https://beta.instructor.academy';
  // The addresses the backend's docs use for production (not live yet).
  static const String _productionApi = 'https://api.instructor.academy/api/v1';
  static const String _productionWeb = 'https://instructor.academy';

  /// The API's base URL, ending in `/api/v1`.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: isProduction ? _productionApi : _betaApi,
  );

  /// The web app's address, for links people share (a class's join link).
  static const String webBaseUrl = String.fromEnvironment(
    'WEB_BASE_URL',
    defaultValue: isProduction ? _productionWeb : _betaWeb,
  );

  /// The default addresses for [env], as the constants above pick them.
  static ({String api, String web}) addressesFor(String env) =>
      env == 'production'
      ? (api: _productionApi, web: _productionWeb)
      : (api: _betaApi, web: _betaWeb);
}

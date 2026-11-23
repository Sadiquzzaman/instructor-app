import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:instructor_app/core/config/app_config.dart';

void main() {
  test('the app name is Instructor', () {
    expect(AppConfig.appName, 'Instructor');
  });

  test('builds talk to beta unless APP_ENV or API_BASE_URL is given', () {
    // `flutter test` runs without --dart-define, so this is the default.
    expect(AppConfig.environment, 'beta');
    expect(AppConfig.isProduction, isFalse);
    expect(AppConfig.apiBaseUrl, 'https://api-beta.instructor.academy/api/v1');
    expect(AppConfig.webBaseUrl, 'https://beta.instructor.academy');
  });

  test('the constants pick the addresses for their environment', () {
    final a = AppConfig.addressesFor(AppConfig.environment);
    expect(AppConfig.apiBaseUrl, a.api);
    expect(AppConfig.webBaseUrl, a.web);
  });

  test('production uses the live addresses', () {
    final p = AppConfig.addressesFor('production');
    expect(p.api, 'https://api.instructor.academy/api/v1');
    expect(p.web, 'https://instructor.academy');
    // Anything else is beta, so a typo never points at production.
    expect(AppConfig.addressesFor('prod').api, contains('api-beta'));
  });

  test('every API base URL is HTTPS and ends in /api/v1', () {
    for (final env in ['beta', 'production']) {
      final uri = Uri.parse(AppConfig.addressesFor(env).api);
      expect(uri.scheme, 'https');
      expect(uri.path, endsWith('/api/v1'));
    }
  });

  test('test APKs always talk to beta; store builds follow APP_ENV', () {
    final pre = File('.github/workflows/android-prerelease.yml')
        .readAsStringSync();
    expect(pre, contains('--dart-define=APP_ENV=beta'));
    final store = File('.github/workflows/store-release.yml')
        .readAsStringSync();
    expect(store, contains(r"APP_ENV: ${{ vars.APP_ENV || 'beta' }}"));
    expect(store, contains(r'--dart-define=APP_ENV=${{ env.APP_ENV }}'));
  });
}

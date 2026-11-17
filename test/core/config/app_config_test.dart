import 'package:flutter_test/flutter_test.dart';

import 'package:instructor_app/core/config/app_config.dart';

void main() {
  test('the app name is Instructor', () {
    expect(AppConfig.appName, 'Instructor');
  });

  test('builds talk to beta unless API_BASE_URL is given', () {
    // `flutter test` runs without --dart-define, so this is the default.
    expect(AppConfig.apiBaseUrl, 'https://api-beta.instructor.academy/api/v1');
  });

  test('the API base URL is HTTPS and ends in /api/v1', () {
    final uri = Uri.parse(AppConfig.apiBaseUrl);
    expect(uri.scheme, 'https');
    expect(uri.path, endsWith('/api/v1'));
  });
}

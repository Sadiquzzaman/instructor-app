import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_response.dart';
import 'package:instructor_app/core/api/safe_log_interceptor.dart';
import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/auth/session_store.dart';
import 'package:instructor_app/core/device/device_info.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';

void main() {
  group('ApiException.fromResponse', () {
    test('a plain message', () {
      final e = ApiException.fromResponse(404, {
        'statusCode': 404,
        'error': true,
        'message': 'Not found',
      });
      expect(e.kind, ApiErrorKind.notFound);
      expect(e.messages, ['Not found']);
      expect(e.code, isNull);
    });

    test('validation: the whole Nest error object in message', () {
      final e = ApiException.fromResponse(400, {
        'statusCode': 400,
        'error': true,
        'message': {
          'message': ['Email must be valid', 'Password is required'],
          'error': 'Bad Request',
          'statusCode': 400,
        },
      });
      expect(e.kind, ApiErrorKind.badRequest);
      expect(e.messages, ['Email must be valid', 'Password is required']);
    });

    test('codes, features and limits', () {
      final e = ApiException.fromResponse(403, {
        'message': 'Limit',
        'code': 'PLAN_LIMIT_REACHED',
        'limit': 'max_storage_mb',
      });
      expect(e.isPlanLimit, isTrue);
      expect(e.limit, 'max_storage_mb');
    });

    test('kinds by status', () {
      expect(ApiException.fromResponse(409, null).kind, ApiErrorKind.conflict);
      expect(
        ApiException.fromResponse(502, '<html>').kind,
        ApiErrorKind.server,
      );
      expect(ApiException.fromResponse(502, null).isTransient, isTrue);
    });

    test('timeouts', () {
      final e = ApiException.fromDio(
        DioException.receiveTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: RequestOptions(path: '/x'),
        ),
      );
      expect(e.kind, ApiErrorKind.timeout);
    });
  });

  group('ApiResponse', () {
    test('a non-envelope body is kept whole', () {
      expect(ApiResponse.fromJson([1, 2]).payload, [1, 2]);
    });

    test('object and list check their type', () {
      expect(
        () => ApiResponse.fromJson({'payload': <Object?>[]}).object,
        throwsFormatException,
      );
      expect(
        () => ApiResponse.fromJson({'payload': <String, Object?>{}}).list,
        throwsFormatException,
      );
    });
  });

  group('Session', () {
    test('organisation session from the sign-in answer', () {
      final s = Session.fromPayload(sessionPayload());
      expect(s.isOrganization, isTrue);
      expect(s.organizationId, 'org-1');
      expect(s.memberRole, 'STUDENT');
      expect(s.organizationDefaultLocale, 'bn');
      expect(s.workspaceType, 'ACADEMIC');
    });

    test('a personal session has no organisation, even if one is sent', () {
      final p = sessionPayload(organizationId: null)
        ..['organization'] = {'id': 'org-x', 'role': 'OWNER'};
      final s = Session.fromPayload(p);
      expect(s.isOrganization, isFalse);
      expect(s.organizationId, isNull);
      expect(s.memberRole, isNull);
    });

    test('missing tokens are refused', () {
      expect(
        () => Session.fromPayload(sessionPayload()..remove('refresh_token')),
        throwsFormatException,
      );
    });

    test('round-trips for storage and never prints tokens', () {
      final s = testSession();
      final back = Session.fromJson(s.toJson());
      expect(back.toJson(), s.toJson());
      expect(s.toString(), isNot(contains('access-1')));
      expect(s.toString(), isNot(contains('refresh-1')));
    });
  });

  group('SecureSessionStore', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('writes, reads and clears', () async {
      final store = SecureSessionStore();
      expect(await store.read(), isNull);
      await store.write(testSession());
      expect((await store.read())!.refreshToken, 'refresh-1');
      await store.clear();
      expect(await store.read(), isNull);
    });

    test('a broken record is dropped (sign in again)', () async {
      FlutterSecureStorage.setMockInitialValues({'session': '{not json'});
      final store = SecureSessionStore();
      expect(await store.read(), isNull);
      expect(await const FlutterSecureStorage().read(key: 'session'), isNull);
    });
  });

  test('DeviceInfo keeps to the API limits', () {
    final d = DeviceInfo(
      platform: 'ANDROID',
      name: 'x' * 200,
      appVersion: '1.0.0+${'9' * 40}',
    ).toJson();
    expect(d['name']!.length, DeviceInfo.maxName);
    expect(d['app_version']!.length, DeviceInfo.maxVersion);
  });

  test('the debug log never shows query values', () {
    final line = SafeLogInterceptor.line(
      RequestOptions(
        path: '/auth/forgot-password',
        method: 'POST',
        queryParameters: {'phone': '01100000000'},
      ),
      200,
    );
    expect(line, 'API POST /auth/forgot-password?phone=… → 200');
    expect(line, isNot(contains('0110')));
  });

  test('errors become a sentence', () {
    final l10n = AppLocalizationsEn();
    expect(
      apiErrorText(l10n, const ApiException(kind: ApiErrorKind.network)),
      l10n.appNoConnection,
    );
    expect(
      apiErrorText(l10n, const ApiException(kind: ApiErrorKind.server)),
      l10n.uiErrorTitle,
    );
  });
}

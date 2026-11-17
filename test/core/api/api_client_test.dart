import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/auth/session_holder.dart';
import 'package:instructor_app/core/device/device_info.dart';

import '../../helpers/fake_api.dart';

void main() {
  late FakeApi api;
  late MemorySessionStore store;
  late SessionHolder sessions;
  late ApiClient client;
  late int expired;

  const device = DeviceInfo(
    platform: 'ANDROID',
    name: 'Google Pixel 8',
    appVersion: '0.1.0',
  );

  Future<void> setUpWith(Session? session) async {
    api = FakeApi();
    store = MemorySessionStore(session);
    sessions = SessionHolder(store);
    await sessions.restore();
    expired = 0;
    client = ApiClient(
      baseUrl: 'https://api.test/api/v1',
      sessions: sessions,
      device: () async => device,
      onSessionExpired: () async {
        expired++;
        await sessions.clear();
      },
      adapter: api,
    );
  }

  group('headers', () {
    test('organisation session: bearer token and X-Organization-Id', () async {
      await setUpWith(testSession());
      api.on('GET /me/entitlements', (_) => ok({}));
      await client.get('/me/entitlements');
      final r = api.requests.single;
      expect(r.bearer, 'access-1');
      expect(r.organizationHeader, 'org-1');
    });

    test('personal session: bearer token, no organisation header', () async {
      await setUpWith(testSession(organizationId: null));
      api.on('GET /me/entitlements', (_) => ok({}));
      await client.get('/me/entitlements');
      final r = api.requests.single;
      expect(r.bearer, 'access-1');
      expect(r.organizationHeader, isNull);
    });

    test('auth: false sends neither (sign-in, sign-up)', () async {
      await setUpWith(testSession());
      api.on('POST /auth/login', (_) => ok(sessionPayload()));
      await client.post('/auth/login', data: {}, auth: false);
      expect(api.requests.single.headers.containsKey('Authorization'), isFalse);
      expect(api.requests.single.organizationHeader, isNull);
    });

    test('signed out: no headers', () async {
      await setUpWith(null);
      api.on('GET /app/version', (_) => ok({'update': 'NONE'}));
      await client.get('/app/version');
      expect(api.requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test('null query values are left out', () async {
      await setUpWith(testSession());
      api.on('GET /me/notifications', (_) => ok([]));
      await client.get('/me/notifications', query: {'page': 1, 'limit': null});
      expect(api.requests.single.query, {'page': 1});
    });
  });

  group('answers and errors', () {
    test('payload and meta come back as ApiResponse', () async {
      await setUpWith(testSession());
      api.on(
        'GET /me/notifications',
        (_) => ok(
          [
            {'id': 'n1'},
          ],
          meta: {
            'page': 1,
            'limit': 20,
            'total': 21,
            'total_pages': 2,
            'unread': 3,
          },
        ),
      );
      final r = await client.get('/me/notifications');
      expect(r.list.single['id'], 'n1');
      expect(r.meta!.hasNext, isTrue);
      expect(r.meta!.extra['unread'], 3);
    });

    test('error codes come through as ApiException', () async {
      await setUpWith(testSession());
      api.on(
        'GET /attendance/me/today',
        (_) =>
            apiError(403, code: 'FEATURE_NOT_IN_PLAN', feature: 'attendance'),
      );
      await expectLater(
        client.get('/attendance/me/today'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.forbidden)
              .having((e) => e.isFeatureLocked, 'locked', isTrue)
              .having((e) => e.feature, 'feature', 'attendance'),
        ),
      );
    });

    test('no connection is a network error', () async {
      await setUpWith(testSession());
      api.on(
        'GET /x',
        (r) => throw DioException.connectionError(
          requestOptions: RequestOptions(path: '/x'),
          reason: 'offline',
        ),
      );
      await expectLater(
        client.get('/x'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.network,
          ),
        ),
      );
    });
  });

  group('refresh on 401', () {
    void serveProtected() {
      // Accepts only the newest access token.
      api.on(
        'GET /auth/profile',
        (r) =>
            r.bearer == sessions.current?.accessToken && r.bearer != 'access-1'
            ? ok({'id': 'user-1'})
            : apiError(401, message: 'Unauthorized'),
      );
    }

    test('refreshes once, stores the new pair, retries with it', () async {
      await setUpWith(testSession());
      serveProtected();
      api.on('POST /auth/refresh', (r) {
        // The new pair must be stored before the request is retried.
        return ok(sessionPayload(access: 'access-2', refresh: 'refresh-2'));
      });

      final r = await client.get('/auth/profile');

      expect(r.object['id'], 'user-1');
      final refresh = api.to('POST /auth/refresh').single;
      expect(refresh.body, {
        'refreshToken': 'refresh-1',
        'organization_id': 'org-1',
        'device': {
          'platform': 'ANDROID',
          'name': 'Google Pixel 8',
          'app_version': '0.1.0',
        },
      });
      final profileCalls = api.to('GET /auth/profile');
      expect(profileCalls.map((c) => c.bearer), ['access-1', 'access-2']);
      expect(store.session!.refreshToken, 'refresh-2');
      expect(store.writes.single.accessToken, 'access-2');
    });

    test('a personal session refreshes without organization_id', () async {
      await setUpWith(testSession(organizationId: null));
      serveProtected();
      api.on(
        'POST /auth/refresh',
        (_) => ok(sessionPayload(access: 'access-2', organizationId: null)),
      );
      await client.get('/auth/profile');
      final body = api.to('POST /auth/refresh').single.body! as Map;
      expect(body.containsKey('organization_id'), isFalse);
    });

    test('several 401s at once share one refresh', () async {
      await setUpWith(testSession());
      serveProtected();
      final release = Completer<void>();
      api.on('POST /auth/refresh', (_) async {
        await release.future;
        return ok(sessionPayload(access: 'access-2', refresh: 'refresh-2'));
      });

      final calls = [for (var i = 0; i < 3; i++) client.get('/auth/profile')];
      await Future<void>.delayed(const Duration(milliseconds: 20));
      release.complete();
      final results = await Future.wait(calls);

      expect(results, hasLength(3));
      expect(api.to('POST /auth/refresh'), hasLength(1));
      expect(client.refresher.calls, 1);
    });

    test('a refused refresh signs out', () async {
      await setUpWith(testSession());
      serveProtected();
      api.on(
        'POST /auth/refresh',
        (_) => apiError(401, message: 'Invalid refresh token'),
      );

      await expectLater(
        client.get('/auth/profile'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.unauthorized,
          ),
        ),
      );
      expect(expired, 1);
      expect(sessions.current, isNull);
      expect(store.session, isNull);
    });

    test('no connection during the refresh keeps the session', () async {
      await setUpWith(testSession());
      serveProtected();
      api.on(
        'POST /auth/refresh',
        (r) => throw DioException.connectionError(
          requestOptions: RequestOptions(path: '/auth/refresh'),
          reason: 'offline',
        ),
      );

      await expectLater(
        client.get('/auth/profile'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.network,
          ),
        ),
      );
      expect(expired, 0);
      expect(sessions.current!.refreshToken, 'refresh-1');
    });

    test('still 401 after a fresh token: signs out, no loop', () async {
      await setUpWith(testSession());
      api.on('GET /auth/profile', (_) => apiError(401));
      api.on(
        'POST /auth/refresh',
        (_) => ok(sessionPayload(access: 'access-2', refresh: 'refresh-2')),
      );

      await expectLater(
        client.get('/auth/profile'),
        throwsA(isA<ApiException>()),
      );
      expect(api.to('GET /auth/profile'), hasLength(2));
      expect(api.to('POST /auth/refresh'), hasLength(1));
      expect(expired, 1);
    });

    test('a 401 from login is a wrong password, not a refresh', () async {
      await setUpWith(testSession());
      api.on(
        'POST /auth/login',
        (_) => apiError(401, message: 'Invalid credentials'),
      );
      await expectLater(
        client.post('/auth/login', data: {}, auth: false),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.unauthorized,
          ),
        ),
      );
      expect(api.to('POST /auth/refresh'), isEmpty);
      expect(expired, 0);
    });
  });
}

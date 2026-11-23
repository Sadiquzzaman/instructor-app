import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/auth/session_store.dart';

/// A request the fake API received.
class FakeRequest {
  FakeRequest(this.method, this.path, this.headers, this.body, this.query);
  final String method;
  final String path;
  final Map<String, dynamic> headers;
  final Object? body;
  final Map<String, dynamic> query;

  String? get bearer =>
      (headers['Authorization'] as String?)?.replaceFirst('Bearer ', '');
  String? get organizationHeader => headers['X-Organization-Id'] as String?;
}

/// What a route answers: a status and a JSON body.
typedef FakeReply = (int status, Object? body);
typedef FakeHandler = FutureOr<FakeReply> Function(FakeRequest request);

/// An in-process API for tests: routes by "METHOD /path", records requests.
/// A route can throw a [DioException] to simulate no connection.
class FakeApi implements HttpClientAdapter {
  final routes = <String, FakeHandler>{};
  final requests = <FakeRequest>[];

  void on(String route, FakeHandler handler) => routes[route] = handler;

  List<FakeRequest> to(String route) =>
      requests.where((r) => '${r.method} ${r.path}' == route).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = Uri.parse(options.uri.toString()).path
        .replaceFirst('/api/v1', '');
    final request = FakeRequest(
      options.method,
      path,
      Map.of(options.headers),
      options.data,
      Map.of(options.queryParameters),
    );
    requests.add(request);
    final handler = routes['${options.method} $path'];
    if (handler == null) {
      return _json(404, {
        'statusCode': 404,
        'error': true,
        'message': 'Not found',
      });
    }
    final (status, body) = await handler(request);
    return _json(status, body);
  }

  ResponseBody _json(int status, Object? body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

/// `{ statusCode: 200, payload, error: false }`.
FakeReply ok(Object? payload, {Map<String, Object?>? meta}) => (
  200,
  {
    'statusCode': 200,
    'message': 'OK',
    'payload': payload,
    'meta': ?meta,
    'error': false,
  },
);

/// An API error body.
FakeReply apiError(
  int status, {
  String? code,
  Object? message,
  String? feature,
  Object? details,
}) => (
  status,
  {
    'statusCode': status,
    'error': true,
    'timestamp': '2026-11-17T00:00:00.000Z',
    'path': '/x',
    'message': message ?? 'Failed',
    'code': ?code,
    'feature': ?feature,
    'details': ?details,
  },
);

/// A login/refresh payload.
Map<String, dynamic> sessionPayload({
  String access = 'access-1',
  String refresh = 'refresh-1',
  String? organizationId = 'org-1',
}) => {
  'id': 'user-1',
  'full_name': 'Test Student',
  'role': 'STUDENT',
  'locale': 'en',
  'context_type': organizationId != null ? 'organization' : 'personal_teacher',
  'session_mode': organizationId != null ? 'organization' : 'individual',
  'workspace_type': 'ACADEMIC',
  'organization': organizationId == null
      ? null
      : {
          'id': organizationId,
          'name': 'Demo School',
          'role': 'STUDENT',
          'status': 'approved',
          'default_locale': 'bn',
          'workspace_type': 'ACADEMIC',
        },
  'access_token': access,
  'refresh_token': refresh,
};

Session testSession({
  String access = 'access-1',
  String refresh = 'refresh-1',
  String? organizationId = 'org-1',
}) => Session.fromPayload(
  sessionPayload(
    access: access,
    refresh: refresh,
    organizationId: organizationId,
  ),
);

/// A [SessionStore] in memory that remembers every write.
class MemorySessionStore implements SessionStore {
  MemorySessionStore([this.session]);
  Session? session;
  final writes = <Session>[];

  @override
  Future<Session?> read() async => session;

  @override
  Future<void> write(Session s) async {
    session = s;
    writes.add(s);
  }

  @override
  Future<void> clear() async => session = null;
}

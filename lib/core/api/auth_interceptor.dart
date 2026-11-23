import 'package:dio/dio.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/token_refresher.dart';
import 'package:instructor_app/core/auth/session_holder.dart';

/// Adds the session to every request and refreshes once on a 401
/// (API guide §3–4):
///
/// - `Authorization: Bearer <access_token>` when signed in;
/// - `X-Organization-Id` only in an organisation session, from the session the
///   API gave us (the API refuses a header that does not match the token);
/// - on a 401: refresh (one at a time), retry once with the new token; if the
///   refresh is refused, sign out ([onSessionExpired]); if it fails for lack
///   of a connection, keep the session and report the network error.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.dio,
    required this.sessions,
    required this.refresher,
    required this.onSessionExpired,
  });

  /// The client's own Dio, to retry the original request through every
  /// interceptor again.
  final Dio dio;
  final SessionHolder sessions;
  final TokenRefresher refresher;
  final Future<void> Function() onSessionExpired;

  /// Set on a request to send it without the session (sign-in, sign-up).
  static const noAuth = 'noAuth';
  static const _retried = 'authRetried';

  /// Never refreshed: these do their own thing with tokens.
  static const _noRefreshPaths = {
    '/auth/login',
    '/auth/login/organization',
    '/auth/refresh',
    '/auth/logout',
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _applySession(options);
    handler.next(options);
  }

  void _applySession(RequestOptions options) {
    options.headers.remove('Authorization');
    options.headers.remove('X-Organization-Id');
    if (options.extra[noAuth] == true) return;
    final session = sessions.current;
    if (session == null) return;
    options.headers['Authorization'] = 'Bearer ${session.accessToken}';
    if (session.isOrganization) {
      options.headers['X-Organization-Id'] = session.organizationId;
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final eligible =
        err.response?.statusCode == 401 &&
        options.extra[noAuth] != true &&
        options.extra[_retried] != true &&
        !_noRefreshPaths.contains(options.path) &&
        sessions.current != null;
    if (!eligible) return handler.next(err);

    final sentToken = (options.headers['Authorization'] as String?)
        ?.replaceFirst('Bearer ', '');
    try {
      // Another request may already have refreshed while this one was out.
      if (sentToken == sessions.current?.accessToken) {
        await refresher.refresh();
      }
    } on ApiException catch (e) {
      if (e.isTransient) {
        // No connection: keep the session; the user can try again.
        return handler.next(
          DioException(requestOptions: options, error: e, type: err.type),
        );
      }
      await onSessionExpired();
      return handler.next(
        DioException(
          requestOptions: options,
          response: err.response,
          error: const ApiException(
            kind: ApiErrorKind.unauthorized,
            statusCode: 401,
          ),
          type: DioExceptionType.badResponse,
        ),
      );
    }

    options.extra[_retried] = true;
    try {
      handler.resolve(await dio.fetch<Object?>(options));
    } on DioException catch (retryError) {
      if (retryError.response?.statusCode == 401) {
        // Refused even with a fresh token: the session is over.
        await onSessionExpired();
      }
      handler.next(retryError);
    }
  }
}

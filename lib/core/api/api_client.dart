import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_response.dart';
import 'package:instructor_app/core/api/auth_interceptor.dart';
import 'package:instructor_app/core/api/safe_log_interceptor.dart';
import 'package:instructor_app/core/api/token_refresher.dart';
import 'package:instructor_app/core/auth/session_holder.dart';
import 'package:instructor_app/core/device/device_info.dart';

/// The app's one way to call the API. Answers come back as [ApiResponse]
/// (the envelope's `payload` and `meta`); every failure is an
/// [ApiException]. The session, the organisation header and the refresh are
/// handled by [AuthInterceptor].
class ApiClient {
  ApiClient._(this._dio, this._bare, this.refresher);

  factory ApiClient({
    required String baseUrl,
    required SessionHolder sessions,
    required Future<DeviceInfo> Function() device,
    required Future<void> Function() onSessionExpired,
    HttpClientAdapter? adapter,
  }) {
    BaseOptions options() => BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    );

    // The refresh goes through a bare Dio, so it can never refresh itself.
    final bare = Dio(options());
    final dio = Dio(options());
    if (adapter != null) {
      bare.httpClientAdapter = adapter;
      dio.httpClientAdapter = adapter;
    }
    final refresher = TokenRefresher(
      dio: bare,
      sessions: sessions,
      device: device,
    );
    dio.interceptors.add(
      AuthInterceptor(
        dio: dio,
        sessions: sessions,
        refresher: refresher,
        onSessionExpired: onSessionExpired,
      ),
    );
    if (kDebugMode) {
      dio.interceptors.add(SafeLogInterceptor());
      bare.interceptors.add(SafeLogInterceptor());
    }
    return ApiClient._(dio, bare, refresher);
  }

  final Dio _dio;

  /// Without the session headers: the refresh, and uploads to signed links.
  final Dio _bare;

  /// Exposed for tests (how many refreshes were sent).
  final TokenRefresher refresher;

  Future<ApiResponse> get(
    String path, {
    Map<String, Object?>? query,
    bool auth = true,
  }) => _send('GET', path, query: query, auth: auth);

  Future<ApiResponse> post(
    String path, {
    Object? data,
    Map<String, Object?>? query,
    bool auth = true,
  }) => _send('POST', path, data: data, query: query, auth: auth);

  Future<ApiResponse> put(String path, {Object? data, bool auth = true}) =>
      _send('PUT', path, data: data, auth: auth);

  Future<ApiResponse> patch(String path, {Object? data, bool auth = true}) =>
      _send('PATCH', path, data: data, auth: auth);

  Future<ApiResponse> delete(String path, {Object? data, bool auth = true}) =>
      _send('DELETE', path, data: data, auth: auth);

  /// Sends a file's bytes to a signed upload link from `POST /files/presign`
  /// (API guide §6). The link is not the API: no session or organisation
  /// headers, only the [headers] the link was signed with. [onProgress] gets
  /// 0 to 1. A cancelled upload throws [ApiErrorKind.cancelled].
  Future<void> putFile(
    Uri url, {
    required Stream<List<int>> data,
    required int length,
    Map<String, String> headers = const {},
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final contentType = headers.entries
        .where((h) => h.key.toLowerCase() == 'content-type')
        .map((h) => h.value)
        .firstOrNull;
    try {
      await _bare.putUri<Object?>(
        url,
        data: data,
        options: Options(
          headers: {...headers, Headers.contentLengthHeader: length},
          contentType: contentType,
          responseType: ResponseType.plain,
        ),
        cancelToken: cancelToken,
        onSendProgress: onProgress == null
            ? null
            : (sent, total) =>
                  onProgress(total > 0 ? sent / total : sent / length),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<ApiResponse> _send(
    String method,
    String path, {
    Object? data,
    Map<String, Object?>? query,
    required bool auth,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: query == null
            ? null
            : {for (final MapEntry(:key, :value) in query.entries) key: ?value},
        options: Options(
          method: method,
          extra: {if (!auth) AuthInterceptor.noAuth: true},
        ),
      );
      return ApiResponse.fromJson(response.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

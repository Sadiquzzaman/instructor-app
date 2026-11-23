import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Debug builds only: one line per request with the method, the path, the
/// status and the time. Never headers, bodies or query values, so tokens,
/// passwords, OTPs and phone numbers cannot reach the log (API guide §8).
class SafeLogInterceptor extends Interceptor {
  static const _start = 'safeLogStart';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_start] = DateTime.now();
    handler.next(options);
  }

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    debugPrint(line(response.requestOptions, response.statusCode));
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint(
      line(err.requestOptions, err.response?.statusCode, err.type.name),
    );
    handler.next(err);
  }

  /// `API GET /attendance/me/today?date=… → 200 (123 ms)`.
  static String line(RequestOptions o, int? status, [String? failure]) {
    final started = o.extra[_start];
    final ms = started is DateTime
        ? ' (${DateTime.now().difference(started).inMilliseconds} ms)'
        : '';
    final query = o.queryParameters.isEmpty
        ? ''
        : '?${o.queryParameters.keys.map((k) => '$k=…').join('&')}';
    return 'API ${o.method} ${o.path}$query → ${status ?? failure ?? '?'}$ms';
  }
}

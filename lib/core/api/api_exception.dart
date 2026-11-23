import 'package:dio/dio.dart';

/// What kind of failure, so screens can react without reading messages.
enum ApiErrorKind {
  /// No connection, DNS or TLS failure: nothing reached the server.
  network,

  /// The server did not answer in time.
  timeout,

  /// 400: the request was refused (validation).
  badRequest,

  /// 401 after the one refresh: the session is over.
  unauthorized,

  /// 403. Look at [ApiException.code] (FEATURE_NOT_IN_PLAN, PLAN_LIMIT_REACHED,
  /// NOT_IN_IELTS, NOT_FOR_BRANCH_MANAGERS, GUARDIANS_OFF, …).
  forbidden,
  notFound,
  conflict,

  /// 5xx, including 502 while beta deploys.
  server,

  /// Cancelled by the app.
  cancelled,
  unknown,
}

/// An API error: `{ statusCode, error: true, message, code?, feature?, limit?, details? }`
/// (API guide §2). **Act on [code], never on [message]**: the message is
/// English and for logs. Many errors (sign-in among them) have no code; then
/// [kind] and [statusCode] say what happened.
class ApiException implements Exception {
  const ApiException({
    required this.kind,
    this.statusCode,
    this.code,
    this.feature,
    this.limit,
    this.messages = const [],
    this.details,
  });

  final ApiErrorKind kind;
  final int? statusCode;
  final String? code;

  /// With FEATURE_NOT_IN_PLAN: the feature key.
  final String? feature;

  /// With PLAN_LIMIT_REACHED: the limit key.
  final String? limit;

  /// The server's English messages (one, or several for validation errors).
  final List<String> messages;
  final Object? details;

  bool get isFeatureLocked => code == 'FEATURE_NOT_IN_PLAN';
  bool get isPlanLimit => code == 'PLAN_LIMIT_REACHED';

  /// Worth trying again later (no connection, timeout, 5xx).
  bool get isTransient =>
      kind == ApiErrorKind.network ||
      kind == ApiErrorKind.timeout ||
      kind == ApiErrorKind.server;

  factory ApiException.fromDio(DioException e) {
    if (e.error is ApiException) return e.error! as ApiException;
    switch (e.type) {
      case DioExceptionType.connectionTimeout ||
          DioExceptionType.transformTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout:
        return const ApiException(kind: ApiErrorKind.timeout);
      case DioExceptionType.connectionError || DioExceptionType.badCertificate:
        return const ApiException(kind: ApiErrorKind.network);
      case DioExceptionType.cancel:
        return const ApiException(kind: ApiErrorKind.cancelled);
      case DioExceptionType.badResponse || DioExceptionType.unknown:
        final response = e.response;
        if (response == null) {
          return const ApiException(kind: ApiErrorKind.network);
        }
        return ApiException.fromResponse(response.statusCode, response.data);
    }
  }

  factory ApiException.fromResponse(int? status, Object? body) {
    final b = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    final code = b['code'] is String ? b['code'] as String : null;
    return ApiException(
      kind: _kindFor(status),
      statusCode: status,
      code: code,
      feature: b['feature'] is String ? b['feature'] as String : null,
      limit: b['limit'] is String ? b['limit'] as String : null,
      messages: _messages(b['message']),
      details: b['details'],
    );
  }

  static ApiErrorKind _kindFor(int? status) => switch (status) {
    400 || 422 => ApiErrorKind.badRequest,
    401 => ApiErrorKind.unauthorized,
    403 => ApiErrorKind.forbidden,
    404 => ApiErrorKind.notFound,
    409 => ApiErrorKind.conflict,
    final int s when s >= 500 => ApiErrorKind.server,
    _ => ApiErrorKind.unknown,
  };

  /// `message` is a string, a list of strings, or, for validation errors, the
  /// whole Nest error object `{ message: [...], error, statusCode }`
  /// (tes-taker http-exception.filter.ts).
  static List<String> _messages(Object? m) => switch (m) {
    final String s => [s],
    final List<Object?> l => [for (final x in l) '$x'],
    final Map<String, dynamic> o => _messages(o['message']),
    _ => const [],
  };

  @override
  String toString() =>
      'ApiException($kind, status: $statusCode, code: $code'
      '${feature != null ? ', feature: $feature' : ''}'
      '${limit != null ? ', limit: $limit' : ''}'
      '${messages.isNotEmpty ? ', ${messages.join('; ')}' : ''})';
}

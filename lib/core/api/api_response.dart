import 'package:flutter/foundation.dart';

/// Paging of a list answer: `meta: { page, limit, total, total_pages }`, plus
/// anything else the endpoint adds (for example the inbox's `unread`).
@immutable
class PageMeta {
  const PageMeta({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
    this.extra = const {},
  });

  final int page;
  final int limit;
  final int total;
  final int totalPages;
  final Map<String, Object?> extra;

  bool get hasNext => page < totalPages;

  static PageMeta? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    int n(String k) => (json[k] as num?)?.toInt() ?? 0;
    return PageMeta(
      page: n('page'),
      limit: n('limit'),
      total: n('total'),
      totalPages: n('total_pages'),
      extra: {
        for (final MapEntry(:key, :value) in json.entries)
          if (!{'page', 'limit', 'total', 'total_pages'}.contains(key))
            key: value,
      },
    );
  }
}

/// A successful answer: `{ statusCode, message, payload, meta?, error: false }`.
/// The data is always in [payload] (API guide §2).
@immutable
class ApiResponse {
  const ApiResponse({required this.payload, this.meta, this.message});

  final Object? payload;
  final PageMeta? meta;

  /// English, for logs only.
  final String? message;

  factory ApiResponse.fromJson(Object? body) {
    if (body is Map<String, dynamic> && body.containsKey('payload')) {
      return ApiResponse(
        payload: body['payload'],
        meta: PageMeta.fromJson(body['meta']),
        message: body['message'] is String ? body['message'] as String : null,
      );
    }
    // Not the usual envelope (a redirect or a plain answer): keep it whole.
    return ApiResponse(payload: body);
  }

  /// [payload] as a JSON object; throws [FormatException] otherwise.
  Map<String, dynamic> get object {
    final p = payload;
    if (p is Map<String, dynamic>) return p;
    throw FormatException('Expected an object, got ${p.runtimeType}.');
  }

  /// [payload] as a list of JSON objects; throws [FormatException] otherwise.
  List<Map<String, dynamic>> get list {
    final p = payload;
    if (p is List) return p.cast<Map<String, dynamic>>();
    throw FormatException('Expected a list, got ${p.runtimeType}.');
  }
}

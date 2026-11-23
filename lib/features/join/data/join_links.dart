import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';

/// A link a teacher shares: the web's `/join/class/<id>` or `/join/test/<id>`
/// (`AppConfig.webBaseUrl` builds them, see teacher_classes.dart).
typedef JoinLink = ({String kind, String id});

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Reads a pasted link, from any of the web's addresses or as a bare path;
/// null when it isn't a class or test link.
JoinLink? parseJoinLink(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null) return null;
  if (uri.hasScheme && uri.scheme != 'https' && uri.scheme != 'http') {
    return null;
  }
  final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
  if (parts.length != 3 || parts[0] != 'join') return null;
  if (parts[1] != 'class' && parts[1] != 'test') return null;
  if (!_uuid.hasMatch(parts[2])) return null;
  return (kind: parts[1], id: parts[2]);
}

/// The app's page for a join link.
String joinRoute(JoinLink link) => '/join/${link.kind}/${link.id}';

/// The public summary of a class (`GET /classes/:id` without a token).
@immutable
class JoinClassSummary {
  const JoinClassSummary({required this.name, this.teacher, this.description});

  final String name;
  final String? teacher;
  final String? description;
}

/// The public summary of a test (`GET /exams/:id` without a token).
@immutable
class JoinTestSummary {
  const JoinTestSummary({
    required this.name,
    this.teacher,
    this.minutes,
    this.private = false,
  });

  final String name;
  final String? teacher;
  final int? minutes;

  /// Only the students the teacher chose may take it.
  final bool private;
}

class JoinRepository {
  JoinRepository(this.api);

  final ApiClient api;

  Future<JoinClassSummary> classSummary(String id) async {
    final p = (await api.get('/classes/$id', auth: false)).object;
    return JoinClassSummary(
      name: (p['class_name'] as String?) ?? '',
      teacher: p['created_user_name'] as String?,
      description: p['description'] as String?,
    );
  }

  /// Joins as a student; true when the teacher still has to approve.
  Future<bool> joinClass(String id) async {
    final p = (await api.post(
      '/classes/$id/join',
      data: <String, Object?>{},
    )).payload;
    return p is Map && p['status'] == 'PENDING';
  }

  Future<JoinTestSummary> testSummary(String id) async {
    final p = (await api.get('/exams/$id', auth: false)).object;
    return JoinTestSummary(
      name: (p['test_name'] as String?) ?? '',
      teacher: p['created_user_name'] as String?,
      minutes: (p['duration_minutes'] as num?)?.toInt(),
      private: p['test_audience'] == 'selected_class',
    );
  }
}

final joinRepositoryProvider = Provider<JoinRepository>(
  (ref) => JoinRepository(ref.watch(apiClientProvider)),
);

final joinClassSummaryProvider = FutureProvider.autoDispose
    .family<JoinClassSummary, String>(
      (ref, id) => ref.read(joinRepositoryProvider).classSummary(id),
      retry: (retryCount, error) => null,
    );

final joinTestSummaryProvider = FutureProvider.autoDispose
    .family<JoinTestSummary, String>(
      (ref, id) => ref.read(joinRepositoryProvider).testSummary(id),
      retry: (retryCount, error) => null,
    );

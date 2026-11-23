import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_providers.dart';

/// A class the student belongs to (`GET /student/classes`).
@immutable
class StudentClass {
  const StudentClass({
    required this.id,
    required this.name,
    this.workspace,
    this.joinedAt,
  });

  final String id;
  final String name;

  /// The school or teacher it belongs to.
  final String? workspace;
  final DateTime? joinedAt;

  static StudentClass? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return StudentClass(
      id: j['id'] as String,
      name: (j['class_name'] as String?) ?? '',
      workspace: (j['context_label'] ?? j['organization_name']) as String?,
      joinedAt: j['joined_at'] is String
          ? DateTime.tryParse(j['joined_at'] as String)
          : null,
    );
  }
}

typedef Classmate = ({String name, DateTime? joinedAt});

/// `GET /student/classes/:id`: the class and its classmates.
@immutable
class ClassDetail {
  const ClassDetail({
    required this.id,
    required this.name,
    required this.classmates,
    this.description,
    this.joinedAt,
  });

  final String id;
  final String name;
  final String? description;
  final DateTime? joinedAt;
  final List<Classmate> classmates;

  static ClassDetail? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final mates = j['classmates'];
    DateTime? time(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return ClassDetail(
      id: j['id'] as String,
      name: (j['class_name'] as String?) ?? '',
      description: j['description'] as String?,
      joinedAt: time(j['joined_at']),
      classmates: [
        if (mates is List)
          for (final m in mates)
            if (m is Map && m['name'] is String)
              (name: m['name'] as String, joinedAt: time(m['joined_at'])),
      ],
    );
  }
}

final myClassesProvider = FutureProvider.autoDispose<List<StudentClass>>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  final p = (await ref.read(apiClientProvider).get('/student/classes')).payload;
  return [
    if (p is List)
      for (final c in p) ?StudentClass.fromJson(c),
  ];
}, retry: (retryCount, error) => null);

final classDetailProvider = FutureProvider.autoDispose
    .family<ClassDetail?, String>((ref, id) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref.read(apiClientProvider).get('/student/classes/$id');
      return ClassDetail.fromJson(r.payload);
    }, retry: (retryCount, error) => null);

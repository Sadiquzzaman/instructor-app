import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/config/app_config.dart';

/// A student on a teacher's class (`classStudents`): JOINED, INVITED or
/// PENDING (asked to join, waiting for the teacher).
@immutable
class ClassMember {
  const ClassMember({
    required this.id,
    required this.studentId,
    required this.status,
    this.name,
    this.email,
    this.phone,
    this.publicId,
    this.invitedEmail,
    this.invitedPhone,
    this.joinedAt,
    this.sectionId,
    this.sectionName,
  });

  final String id;
  final String studentId;
  final String status;
  final String? name;
  final String? email;
  final String? phone;

  /// The student's public Student ID.
  final String? publicId;
  final String? invitedEmail;
  final String? invitedPhone;
  final DateTime? joinedAt;
  final String? sectionId;
  final String? sectionName;

  bool get pending => status == 'PENDING';

  /// Email or phone, or null (the web shows "—").
  String? get contact => [
    email,
    phone,
    invitedEmail,
    invitedPhone,
  ].firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);

  static String? _s(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;

  static ClassMember? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final s = j['student'] is Map
        ? j['student'] as Map
        : const <String, Object?>{};
    final sec = j['section'] is Map
        ? j['section'] as Map
        : const <String, Object?>{};
    return ClassMember(
      id: j['id'] as String,
      studentId: (j['student_id'] as String?) ?? (s['id'] as String?) ?? '',
      status: (j['status'] as String?) ?? 'INVITED',
      name: _s(s['full_name']),
      email: _s(s['email']),
      phone: _s(s['phone']),
      publicId: _s(s['student_public_id']),
      invitedEmail: _s(j['invited_email']),
      invitedPhone: _s(j['invited_phone']),
      joinedAt: j['joined_at'] is String
          ? DateTime.tryParse(j['joined_at'] as String)
          : null,
      sectionId: sec['id'] as String?,
      sectionName: sec['name'] as String?,
    );
  }
}

/// A teacher's class (`GET /classes`, `GET /classes/:id`).
@immutable
class TeacherClass {
  const TeacherClass({
    required this.id,
    required this.name,
    required this.members,
    this.description,
    this.testsTaken = 0,
    this.lastTestAt,
  });

  final String id;
  final String name;
  final String? description;
  final List<ClassMember> members;
  final int testsTaken;
  final DateTime? lastTestAt;

  static TeacherClass? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final m = j['classStudents'];
    return TeacherClass(
      id: j['id'] as String,
      name: (j['class_name'] as String?) ?? '',
      description: j['description'] as String?,
      testsTaken: (j['total_test_taken'] as num?)?.toInt() ?? 0,
      lastTestAt: j['last_test_taken_date'] is String
          ? DateTime.tryParse(j['last_test_taken_date'] as String)
          : null,
      members: [
        if (m is List)
          for (final x in m) ?ClassMember.fromJson(x),
      ],
    );
  }
}

/// The web's join link for a class: anyone with it can ask to join.
String classJoinLink(String classId) =>
    '${AppConfig.webBaseUrl}/join/class/${Uri.encodeComponent(classId)}';

final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final _digits = RegExp(r'^\d+$');
final _publicId = RegExp(r'^\d{5,8}$');

/// Why an entry to invite is not an email, an 11-digit phone or a Student
/// ID (the web's `getValidationError`): `email`, `input` or `phone`; null
/// when it is fine.
String? inviteProblem(String input) {
  final t = input.trim();
  if (t.contains('@')) return _email.hasMatch(t) ? null : 'email';
  if (_publicId.hasMatch(t)) return null;
  if (!_digits.hasMatch(t)) return 'input';
  if (t.length != 11) return 'phone';
  return null;
}

/// The same entry as the web compares it (emails ignore case).
String normalizeInvite(String input) {
  final t = input.trim();
  return t.contains('@') ? t.toLowerCase() : t;
}

class TeacherClassesRepository {
  TeacherClassesRepository(this._api);

  final ApiClient _api;

  Future<List<TeacherClass>> all() async {
    final p = (await _api.get('/classes')).payload;
    return [
      if (p is List)
        for (final c in p) ?TeacherClass.fromJson(c),
    ];
  }

  Future<TeacherClass?> one(String id) async =>
      TeacherClass.fromJson((await _api.get('/classes/$id')).payload);

  /// Creates a class; [students] are emails, phones or Student IDs to invite.
  Future<TeacherClass?> create({
    required String name,
    String description = '',
    List<String> students = const [],
  }) async => TeacherClass.fromJson(
    (await _api.post(
      '/classes',
      data: {
        'class_name': name,
        'description': description,
        'students': students,
      },
    )).payload,
  );

  /// Invites students; returns the class as it is now.
  Future<TeacherClass?> invite(String id, List<String> students) async =>
      TeacherClass.fromJson(
        (await _api.post(
          '/classes/$id/students',
          data: {'students': students},
        )).payload,
      );

  Future<void> approve(String id, String studentId) => _api.post(
    '/classes/$id/students/$studentId/approve',
    data: const <String, Object>{},
  );

  /// Removes students (or turns down someone who asked to join).
  Future<void> remove(String id, List<String> studentIds) =>
      _api.delete('/classes/$id/students', data: {'student_ids': studentIds});
}

final teacherClassesRepositoryProvider = Provider<TeacherClassesRepository>(
  (ref) => TeacherClassesRepository(ref.watch(apiClientProvider)),
);

final teacherClassesProvider = FutureProvider.autoDispose<List<TeacherClass>>((
  ref,
) {
  ref.watch(workspaceKeyProvider);
  return ref.read(teacherClassesRepositoryProvider).all();
}, retry: (retryCount, error) => null);

final teacherClassProvider = FutureProvider.autoDispose
    .family<TeacherClass?, String>((ref, id) {
      ref.watch(workspaceKeyProvider);
      return ref.read(teacherClassesRepositoryProvider).one(id);
    }, retry: (retryCount, error) => null);

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_providers.dart';

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

List<T> _list<T>(Object? v, T? Function(Map<Object?, Object?>) read) => [
  if (v is List)
    for (final i in v)
      if (i is Map) ?read(i),
];

/// A test running now.
@immutable
class LiveTest {
  const LiveTest({
    required this.id,
    required this.participants,
    required this.submitted,
    required this.remainingSeconds,
    this.name,
    this.className,
  });

  final String id;
  final String? name;
  final String? className;
  final int participants;
  final int submitted;

  /// When the answer was made; the screen counts down from it.
  final int remainingSeconds;

  static LiveTest? fromJson(Map<Object?, Object?> j) => j['id'] is String
      ? LiveTest(
          id: j['id'] as String,
          name: j['test_name'] as String?,
          className: j['class_name'] as String?,
          participants: _int(j['participant_count']),
          submitted: _int(j['submitted_count']),
          remainingSeconds: _int(j['remaining_seconds']),
        )
      : null;
}

/// A scheduled test.
@immutable
class UpcomingTest {
  const UpcomingTest({
    required this.id,
    required this.startsAt,
    required this.students,
    this.name,
    this.className,
    this.durationMinutes,
  });

  final String id;
  final String? name;
  final String? className;
  final DateTime startsAt;
  final int? durationMinutes;
  final int students;

  static UpcomingTest? fromJson(Map<Object?, Object?> j) {
    final start = DateTime.tryParse((j['exam_start_time'] as String?) ?? '');
    if (j['id'] is! String || start == null) return null;
    return UpcomingTest(
      id: j['id'] as String,
      name: j['test_name'] as String?,
      className: j['class_name'] as String?,
      startsAt: start,
      durationMinutes: (j['duration_minutes'] as num?)?.toInt(),
      students: _int(j['student_count']),
    );
  }
}

typedef ClassSummary = ({String id, String name, int students});

typedef TopStudent = ({
  String id,
  String name,
  int testsTaken,
  double? averagePercent,
});

typedef TopStudentsOfClass = ({
  String classId,
  String className,
  List<TopStudent> students,
});

/// `GET /dashboard/teacher`: what the web's dashboard shows. The calendar
/// and activity charts stay on the web.
@immutable
class TeacherDashboard {
  const TeacherDashboard({
    this.toMark = 0,
    this.live = const [],
    this.students = (total: 0, active: 0, pending: 0),
    this.upcoming = const [],
    this.classes = const [],
    this.topStudents = const [],
  });

  /// Submissions waiting to be marked.
  final int toMark;
  final List<LiveTest> live;
  final ({int total, int active, int pending}) students;

  /// Soonest first.
  final List<UpcomingTest> upcoming;
  final List<ClassSummary> classes;
  final List<TopStudentsOfClass> topStudents;

  factory TeacherDashboard.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final s = j['students_summary'];
    final sm = s is Map ? s : const <String, Object?>{};
    return TeacherDashboard(
      toMark: _int(j['pending_grading_count']),
      live: _list(j['live_tests'], LiveTest.fromJson),
      students: (
        total: _int(sm['total']),
        active: _int(sm['active']),
        pending: _int(sm['pending']),
      ),
      upcoming: _list(j['upcoming_tests'], UpcomingTest.fromJson)
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt)),
      classes: _list(
        j['classes_summary'],
        (c) => c['id'] is String
            ? (
                id: c['id'] as String,
                name: (c['name'] as String?) ?? '',
                students: _int(c['student_count']),
              )
            : null,
      ),
      topStudents: _list(
        j['top_students_by_class'],
        (c) => c['class_id'] is String
            ? (
                classId: c['class_id'] as String,
                className: (c['class_name'] as String?) ?? '',
                students: _list(
                  c['students'],
                  (s) => s['student_id'] is String
                      ? (
                          id: s['student_id'] as String,
                          name: (s['name'] as String?) ?? '',
                          testsTaken: _int(s['tests_taken']),
                          averagePercent: (s['avg_score_percent'] as num?)
                              ?.toDouble(),
                        )
                      : null,
                ),
              )
            : null,
      ),
    );
  }
}

final teacherDashboardProvider = FutureProvider.autoDispose<TeacherDashboard>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  final r = await ref.read(apiClientProvider).get('/dashboard/teacher');
  return TeacherDashboard.fromJson(r.payload);
}, retry: (retryCount, error) => null);

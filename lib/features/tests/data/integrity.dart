import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/features/tests/data/monitor.dart';

typedef CheckCount = ({String check, int count});

List<CheckCount> _checks(Object? v) => [
  if (v is List)
    for (final c in v)
      if (c is Map && c['check'] is String)
        (
          check: c['check'] as String,
          count: (c['count'] as num?)?.toInt() ?? 0,
        ),
];

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// A student on the integrity report.
typedef IntegrityRow = ({
  String studentId,
  String name,

  /// SUBMITTED, AUTO_SUBMITTED, DISQUALIFIED or IN_PROGRESS.
  String status,
  num? score,
  num? maxScore,
  int flags,
  List<CheckCount> checks,

  /// REINSTATE, RETAKE or CONFIRM.
  String? lastDecision,
});

/// `GET /exams/:id/proctoring/integrity`.
@immutable
class IntegrityReport {
  const IntegrityReport({
    required this.students,
    required this.flagged,
    required this.disqualified,
    required this.reviewed,
    required this.byCheck,
    required this.rows,
  });

  final int students;
  final int flagged;
  final int disqualified;
  final int reviewed;
  final List<({String check, int count, int students})> byCheck;

  /// Most flagged first (the server's order).
  final List<IntegrityRow> rows;

  factory IntegrityReport.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final s = j['summary'] is Map
        ? j['summary'] as Map
        : const <String, Object?>{};
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    return IntegrityReport(
      students: n(s['students']),
      flagged: n(s['flagged']),
      disqualified: n(s['disqualified']),
      reviewed: n(s['reviewed']),
      byCheck: [
        if (j['by_check'] is List)
          for (final c in j['by_check'] as List)
            if (c is Map && c['check'] is String)
              (
                check: c['check'] as String,
                count: n(c['count']),
                students: n(c['students']),
              ),
      ],
      rows: [
        if (j['students'] is List)
          for (final r in j['students'] as List)
            if (r is Map && r['student_id'] is String)
              (
                studentId: r['student_id'] as String,
                name: (r['student_name'] as String?) ?? '',
                status: (r['status'] as String?) ?? '',
                score: r['total_score'] as num?,
                maxScore: r['max_score'] as num?,
                flags: n(r['flags']),
                checks: _checks(r['checks']),
                lastDecision: r['last_review'] is Map
                    ? (r['last_review'] as Map)['decision'] as String?
                    : null,
              ),
      ],
    );
  }
}

/// A review of an attempt.
typedef AttemptReview = ({
  String id,
  String decision,
  String reason,
  DateTime? at,
  String? by,
});

/// `GET /exams/:id/proctoring/students/:studentId/report`.
@immutable
class StudentIntegrity {
  const StudentIntegrity({
    required this.status,
    required this.checks,
    required this.timeline,
    required this.reviews,
    this.score,
    this.maxScore,
    this.why,
  });

  final String status;
  final num? score;
  final num? maxScore;

  /// Why they were disqualified.
  final String? why;
  final List<CheckCount> checks;
  final List<TimelineEvent> timeline;
  final List<AttemptReview> reviews;

  factory StudentIntegrity.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final a = j['attempt'] is Map
        ? j['attempt'] as Map
        : const <String, Object?>{};
    return StudentIntegrity(
      status: (a['status'] as String?) ?? '',
      score: a['total_score'] as num?,
      maxScore: a['max_score'] as num?,
      why: a['disqualification_reason'] as String?,
      checks: _checks(j['checks']),
      timeline: [
        if (j['timeline'] is List)
          for (final e in j['timeline'] as List)
            if (e is Map)
              (
                id: '${e['id'] ?? ''}',
                type: (e['type'] as String?) ?? '',
                at: _time(e['occurred_at']),
                message: e['message'] as String?,
                source: e['source'] as String?,
              ),
      ],
      reviews: [
        if (j['reviews'] is List)
          for (final r in j['reviews'] as List)
            if (r is Map)
              (
                id: '${r['id'] ?? ''}',
                decision: (r['decision'] as String?) ?? '',
                reason: (r['reason'] as String?) ?? '',
                at: _time(r['decided_at']),
                by: r['decided_by_name'] as String?,
              ),
      ],
    );
  }
}

final integrityReportProvider = FutureProvider.autoDispose
    .family<IntegrityReport, String>((ref, examId) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref
          .read(apiClientProvider)
          .get('/exams/$examId/proctoring/integrity');
      return IntegrityReport.fromJson(r.payload);
    }, retry: (retryCount, error) => null);

final studentIntegrityProvider = FutureProvider.autoDispose
    .family<StudentIntegrity, ({String examId, String studentId})>((
      ref,
      k,
    ) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref
          .read(apiClientProvider)
          .get('/exams/${k.examId}/proctoring/students/${k.studentId}/report');
      return StudentIntegrity.fromJson(r.payload);
    }, retry: (retryCount, error) => null);
